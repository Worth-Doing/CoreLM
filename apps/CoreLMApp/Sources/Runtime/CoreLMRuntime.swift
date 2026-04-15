import Foundation
import CCoreLM

@Observable
final class CoreLMRuntime {
    enum State: Equatable {
        case idle
        case loading
        case ready
        case generating
        case error(String)
    }

    private(set) var state: State = .idle
    private(set) var loadedModelInfo: ModelInfo?
    private(set) var metrics: RuntimeMetrics = .empty

    private var contextHandle: clm_context_t?
    private var modelHandle: clm_model_t?
    private var sessionHandle: clm_session_t?

    init() {
        var params = clm_context_default_params()
        // params.backend is already "auto" from default
        params.n_threads = 0
        params.verbose_logging = false

        var ctx: clm_context_t?
        let status = clm_context_create(params, &ctx)
        if status == CLM_STATUS_OK {
            self.contextHandle = ctx
        }
    }

    deinit {
        if let session = sessionHandle { clm_session_destroy(session) }
        if let model = modelHandle { clm_model_unload(model) }
        if let ctx = contextHandle { clm_context_destroy(ctx) }
    }

    // MARK: - Model Management

    func loadModel(at url: URL) async throws {
        guard let ctx = contextHandle else {
            throw CoreLMError.invalidState("No runtime context")
        }

        await MainActor.run { state = .loading }

        // Unload any existing model
        if let session = sessionHandle {
            clm_session_destroy(session)
            sessionHandle = nil
        }
        if let model = modelHandle {
            clm_model_unload(model)
            modelHandle = nil
        }

        let path = url.path

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: CoreLMError.invalidState("Runtime deallocated"))
                    return
                }

                var model: clm_model_t?
                let status = clm_model_load(ctx, path, &model)

                if status != CLM_STATUS_OK {
                    let errorMsg = String(cString: clm_get_last_error(ctx))
                    let error = CoreLMError.from(status: status, message: errorMsg)
                    DispatchQueue.main.async {
                        self.state = .error(error.localizedDescription)
                    }
                    continuation.resume(throwing: error)
                    return
                }

                self.modelHandle = model

                // Get model info
                var info = clm_model_info_t()
                clm_model_get_info(model, &info)

                let modelInfo = ModelInfo(
                    id: UUID(),
                    name: String(cString: info.name),
                    architecture: String(cString: info.architecture),
                    quantization: String(cString: info.quantization),
                    parameterCount: info.parameter_count,
                    fileSizeBytes: info.file_size_bytes,
                    contextLength: Int(info.context_length),
                    embeddingLength: Int(info.embedding_length),
                    numLayers: Int(info.num_layers),
                    numHeads: Int(info.num_heads),
                    numKVHeads: Int(info.num_kv_heads),
                    vocabSize: Int(info.vocab_size),
                    filePath: path,
                    addedAt: Date(),
                    lastLoadedAt: Date()
                )

                // Create default session
                var sessionParams = clm_session_default_params()
                sessionParams.context_size = info.context_length
                var session: clm_session_t?
                let sessionStatus = clm_session_create(ctx, model, sessionParams, &session)
                if sessionStatus == CLM_STATUS_OK {
                    self.sessionHandle = session
                }

                DispatchQueue.main.async {
                    self.loadedModelInfo = modelInfo
                    self.state = .ready
                }
                continuation.resume()
            }
        }
    }

    func unloadModel() {
        if let session = sessionHandle {
            clm_session_destroy(session)
            sessionHandle = nil
        }
        if let model = modelHandle {
            clm_model_unload(model)
            modelHandle = nil
        }
        loadedModelInfo = nil
        metrics = .empty
        state = .idle
    }

    // MARK: - Generation

    func generate(
        prompt: String,
        parameters: GenerationParameters = .default
    ) -> AsyncThrowingStream<Token, Error> {
        guard let session = sessionHandle else {
            return AsyncThrowingStream { $0.finish(throwing: CoreLMError.invalidState("No session")) }
        }

        state = .generating

        return AsyncThrowingStream { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                var params = clm_generation_default_params()
                params.temperature = parameters.temperature
                params.top_k = Int32(parameters.topK)
                params.top_p = parameters.topP
                params.repeat_penalty = parameters.repeatPenalty
                params.max_tokens = Int32(parameters.maxTokens)
                params.seed = parameters.seed

                // Bridge: We need to pass the continuation through the C callback.
                // Use an Unmanaged pointer to a wrapper class.
                let wrapper = TokenCallbackWrapper(continuation: continuation)
                let ptr = Unmanaged.passRetained(wrapper).toOpaque()

                let status = clm_generate(
                    session,
                    prompt,
                    params,
                    { (tokenText, tokenId, userData) -> Bool in
                        guard let userData else { return false }
                        let w = Unmanaged<TokenCallbackWrapper>.fromOpaque(userData).takeUnretainedValue()
                        guard let text = tokenText else { return false }
                        let token = Token(id: Int(tokenId), text: String(cString: text))
                        w.continuation.yield(token)
                        return true
                    },
                    ptr
                )

                Unmanaged<TokenCallbackWrapper>.fromOpaque(ptr).release()

                if status == CLM_STATUS_CANCELLED {
                    continuation.finish()
                } else if status != CLM_STATUS_OK {
                    continuation.finish(throwing: CoreLMError.generationFailed(reason: "status \(status.rawValue)"))
                } else {
                    continuation.finish()
                }

                // Update metrics
                self?.refreshMetrics()

                DispatchQueue.main.async {
                    if self?.state == .generating {
                        self?.state = .ready
                    }
                }
            }
        }
    }

    func cancelGeneration() {
        guard let session = sessionHandle else { return }
        clm_generate_cancel(session)
    }

    func resetSession() {
        guard let session = sessionHandle else { return }
        clm_session_reset(session)
        metrics = .empty
    }

    // MARK: - Metrics

    func refreshMetrics() {
        guard let session = sessionHandle else { return }

        var m = clm_metrics_t()
        let status = clm_get_metrics(session, &m)
        guard status == CLM_STATUS_OK else { return }

        let updated = RuntimeMetrics(
            modelLoadTime: m.model_load_time_ms / 1000.0,
            promptEvalTime: m.prompt_eval_time_ms / 1000.0,
            promptEvalTokens: Int(m.prompt_eval_tokens),
            promptEvalSpeed: m.prompt_eval_tok_per_sec,
            generationTime: m.generation_time_ms / 1000.0,
            generationTokens: Int(m.generation_tokens),
            generationSpeed: m.generation_tok_per_sec,
            timeToFirstToken: m.time_to_first_token_ms / 1000.0,
            memoryModel: m.memory_model_bytes,
            memoryKVCache: m.memory_kv_cache_bytes,
            memoryScratch: m.memory_scratch_bytes,
            contextTokensUsed: Int(m.context_tokens_used),
            contextTokensMax: Int(m.context_tokens_max),
            activeBackend: m.active_backend != nil ? String(cString: m.active_backend) : "CPU"
        )

        DispatchQueue.main.async { [weak self] in
            self?.metrics = updated
        }
    }

    // MARK: - Validation

    static func validateModel(at url: URL) -> (valid: Bool, info: clm_model_info_t?) {
        var info = clm_model_info_t()
        let status = clm_model_validate(url.path, &info)
        if status == CLM_STATUS_OK {
            return (true, info)
        }
        return (false, nil)
    }
}

// MARK: - Supporting Types

struct Token {
    let id: Int
    let text: String
}

enum CoreLMError: LocalizedError {
    case modelLoadFailed(reason: String)
    case unsupportedArchitecture(String)
    case unsupportedQuantization(String)
    case memoryAllocationFailed
    case backendInitFailed(backend: String, reason: String)
    case generationFailed(reason: String)
    case cancelled
    case invalidState(String)
    case fileError(String)

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let r): return "Model load failed: \(r)"
        case .unsupportedArchitecture(let a): return "Unsupported architecture: \(a)"
        case .unsupportedQuantization(let q): return "Unsupported quantization: \(q)"
        case .memoryAllocationFailed: return "Memory allocation failed"
        case .backendInitFailed(let b, let r): return "Backend '\(b)' init failed: \(r)"
        case .generationFailed(let r): return "Generation failed: \(r)"
        case .cancelled: return "Generation cancelled"
        case .invalidState(let s): return "Invalid state: \(s)"
        case .fileError(let f): return "File error: \(f)"
        }
    }

    static func from(status: clm_status_t, message: String) -> CoreLMError {
        switch status {
        case CLM_STATUS_FILE_ERROR:         return .fileError(message)
        case CLM_STATUS_UNSUPPORTED_ARCH:   return .unsupportedArchitecture(message)
        case CLM_STATUS_UNSUPPORTED_QUANT:  return .unsupportedQuantization(message)
        case CLM_STATUS_MEMORY_ERROR:       return .memoryAllocationFailed
        case CLM_STATUS_BACKEND_ERROR:      return .backendInitFailed(backend: "unknown", reason: message)
        case CLM_STATUS_CANCELLED:          return .cancelled
        case CLM_STATUS_INVALID_STATE:      return .invalidState(message)
        case CLM_STATUS_MODEL_ERROR:        return .modelLoadFailed(reason: message)
        default:                            return .generationFailed(reason: message)
        }
    }
}

private class TokenCallbackWrapper {
    let continuation: AsyncThrowingStream<Token, Error>.Continuation
    init(continuation: AsyncThrowingStream<Token, Error>.Continuation) {
        self.continuation = continuation
    }
}
