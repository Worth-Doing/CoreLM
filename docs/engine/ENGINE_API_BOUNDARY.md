# CoreLM — Engine API Boundary Proposal

## Overview

The Engine API Boundary is the contract between the C++ inference engine and the Swift application. It consists of two layers:

1. **C API** (`engine/c_api/`) — a stable, C-compatible function interface
2. **Swift Wrapper** (`apps/CoreLMApp/Sources/Runtime/`) — idiomatic Swift types built on the C API

The C API is the **only** way Swift code may interact with the engine. No C++ headers, classes, or templates are visible to Swift.

---

## C API Design

### Principles

- All functions prefixed with `clm_`
- All handles are opaque pointers (`typedef struct clm_context* clm_context_t`)
- All functions return `clm_status_t` for error reporting
- No C++ types in any header
- No exceptions cross the boundary — all errors are status codes
- All strings are `const char*` (UTF-8, null-terminated)
- Callbacks use C function pointers with `void* user_data`

### Header: `engine/include/corelm.h`

```c
#ifndef CORELM_H
#define CORELM_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ──────────────────────────────────────────────
   Status codes
   ────────────────────────────────────────────── */

typedef enum {
    CLM_STATUS_OK = 0,
    CLM_STATUS_ERROR = 1,
    CLM_STATUS_INVALID_ARG = 2,
    CLM_STATUS_FILE_ERROR = 3,
    CLM_STATUS_UNSUPPORTED_ARCH = 4,
    CLM_STATUS_UNSUPPORTED_QUANT = 5,
    CLM_STATUS_MEMORY_ERROR = 6,
    CLM_STATUS_BACKEND_ERROR = 7,
    CLM_STATUS_CANCELLED = 8,
    CLM_STATUS_INVALID_STATE = 9,
    CLM_STATUS_MODEL_ERROR = 10,
} clm_status_t;

/* Get human-readable error message for last error on this context */
const char* clm_get_last_error(clm_context_t ctx);

/* ──────────────────────────────────────────────
   Opaque handles
   ────────────────────────────────────────────── */

typedef struct clm_context_impl*  clm_context_t;
typedef struct clm_model_impl*    clm_model_t;
typedef struct clm_session_impl*  clm_session_t;

/* ──────────────────────────────────────────────
   Context lifecycle
   ────────────────────────────────────────────── */

typedef struct {
    const char* backend;          /* "auto", "cpu", "metal" */
    int         n_threads;        /* 0 = auto-detect */
    bool        verbose_logging;
} clm_context_params_t;

clm_context_params_t clm_context_default_params(void);

clm_status_t clm_context_create(
    clm_context_params_t params,
    clm_context_t*       out_ctx
);

void clm_context_destroy(clm_context_t ctx);

/* ──────────────────────────────────────────────
   Model loading
   ────────────────────────────────────────────── */

typedef struct {
    const char* architecture;     /* e.g. "llama" */
    const char* name;             /* e.g. "LLaMA 3.2 3B" */
    const char* quantization;     /* e.g. "Q4_0" */
    uint64_t    parameter_count;
    uint64_t    file_size_bytes;
    uint32_t    context_length;
    uint32_t    embedding_length;
    uint32_t    num_layers;
    uint32_t    num_heads;
    uint32_t    num_kv_heads;
    uint32_t    vocab_size;
} clm_model_info_t;

clm_status_t clm_model_load(
    clm_context_t   ctx,
    const char*     file_path,
    clm_model_t*    out_model
);

clm_status_t clm_model_get_info(
    clm_model_t         model,
    clm_model_info_t*   out_info
);

void clm_model_unload(clm_model_t model);

/* Validate a GGUF file without fully loading it */
clm_status_t clm_model_validate(
    const char*         file_path,
    clm_model_info_t*   out_info   /* may be NULL if info not needed */
);

/* ──────────────────────────────────────────────
   Session management
   ────────────────────────────────────────────── */

typedef struct {
    uint32_t context_size;    /* 0 = use model default */
    uint32_t batch_size;      /* 0 = default (512) */
} clm_session_params_t;

clm_session_params_t clm_session_default_params(void);

clm_status_t clm_session_create(
    clm_context_t         ctx,
    clm_model_t           model,
    clm_session_params_t  params,
    clm_session_t*        out_session
);

void clm_session_destroy(clm_session_t session);

clm_status_t clm_session_reset(clm_session_t session);

/* ──────────────────────────────────────────────
   Generation
   ────────────────────────────────────────────── */

typedef struct {
    float    temperature;       /* default: 0.7 */
    int32_t  top_k;             /* default: 40, -1 = disabled */
    float    top_p;             /* default: 0.95, 1.0 = disabled */
    float    repeat_penalty;    /* default: 1.1, 1.0 = disabled */
    int32_t  max_tokens;        /* default: 2048, -1 = unlimited */
    uint64_t seed;              /* 0 = random */
} clm_generation_params_t;

clm_generation_params_t clm_generation_default_params(void);

/* Token callback — called for each generated token.
   Return false to cancel generation. */
typedef bool (*clm_token_callback_t)(
    const char* token_text,    /* UTF-8 token string */
    int32_t     token_id,      /* token ID */
    void*       user_data
);

clm_status_t clm_generate(
    clm_session_t             session,
    const char*               prompt,
    clm_generation_params_t   params,
    clm_token_callback_t      on_token,
    void*                     user_data
);

/* Request cancellation of in-progress generation.
   Thread-safe — can be called from any thread. */
clm_status_t clm_generate_cancel(clm_session_t session);

/* ──────────────────────────────────────────────
   Metrics
   ────────────────────────────────────────────── */

typedef struct {
    double   model_load_time_ms;
    double   prompt_eval_time_ms;
    int32_t  prompt_eval_tokens;
    double   prompt_eval_tok_per_sec;
    double   generation_time_ms;
    int32_t  generation_tokens;
    double   generation_tok_per_sec;
    double   time_to_first_token_ms;
    int64_t  memory_model_bytes;
    int64_t  memory_kv_cache_bytes;
    int64_t  memory_scratch_bytes;
    int32_t  context_tokens_used;
    int32_t  context_tokens_max;
    const char* active_backend;
} clm_metrics_t;

clm_status_t clm_get_metrics(
    clm_session_t   session,
    clm_metrics_t*  out_metrics
);

/* ──────────────────────────────────────────────
   Logging
   ────────────────────────────────────────────── */

typedef enum {
    CLM_LOG_TRACE = 0,
    CLM_LOG_DEBUG = 1,
    CLM_LOG_INFO  = 2,
    CLM_LOG_WARN  = 3,
    CLM_LOG_ERROR = 4,
} clm_log_level_t;

typedef void (*clm_log_callback_t)(
    clm_log_level_t level,
    const char*     message,
    void*           user_data
);

void clm_set_log_callback(
    clm_context_t        ctx,
    clm_log_callback_t   callback,
    void*                user_data,
    clm_log_level_t      min_level
);

#ifdef __cplusplus
}
#endif

#endif /* CORELM_H */
```

---

## Swift Wrapper API

The Swift wrapper translates the C API into idiomatic Swift, providing:

- Memory-safe handle management (`deinit` calls destroy)
- Swift error types instead of status codes
- `AsyncThrowingStream` instead of callbacks
- `@Observable` for reactive UI binding
- `async/await` for lifecycle operations

### CoreLMRuntime

```swift
import Foundation

@Observable
final class CoreLMRuntime {
    enum State: Equatable {
        case idle
        case loading(progress: String)
        case ready(model: ModelInfo)
        case generating
        case error(CoreLMError)
    }

    private(set) var state: State = .idle
    private(set) var metrics: RuntimeMetrics = .empty

    private var contextHandle: clm_context_t?
    private var modelHandle: clm_model_t?

    init(backend: Backend = .auto, threads: Int = 0, verboseLogging: Bool = false) throws {
        var params = clm_context_default_params()
        params.backend = backend.rawValue
        params.n_threads = Int32(threads)
        params.verbose_logging = verboseLogging

        var ctx: clm_context_t?
        try checkStatus(clm_context_create(params, &ctx))
        self.contextHandle = ctx
    }

    deinit {
        if let model = modelHandle { clm_model_unload(model) }
        if let ctx = contextHandle { clm_context_destroy(ctx) }
    }

    // MARK: - Model Management

    func loadModel(at url: URL) async throws {
        state = .loading(progress: "Loading model...")

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self, let ctx = self.contextHandle else {
                    continuation.resume(throwing: CoreLMError.invalidState("No context"))
                    return
                }

                var model: clm_model_t?
                let status = clm_model_load(ctx, url.path, &model)

                if status != CLM_STATUS_OK {
                    let error = CoreLMError.from(status: status, context: ctx)
                    DispatchQueue.main.async { self.state = .error(error) }
                    continuation.resume(throwing: error)
                    return
                }

                var info = clm_model_info_t()
                clm_model_get_info(model, &info)
                let modelInfo = ModelInfo(from: info)

                self.modelHandle = model
                DispatchQueue.main.async { self.state = .ready(model: modelInfo) }
                continuation.resume()
            }
        }
    }

    func unloadModel() async {
        if let model = modelHandle {
            clm_model_unload(model)
            modelHandle = nil
        }
        state = .idle
    }

    // MARK: - Session Factory

    func createSession(
        contextSize: Int = 0,
        batchSize: Int = 0
    ) throws -> InferenceSession {
        guard let ctx = contextHandle, let model = modelHandle else {
            throw CoreLMError.invalidState("No model loaded")
        }
        return try InferenceSession(
            context: ctx,
            model: model,
            contextSize: contextSize,
            batchSize: batchSize
        )
    }

    // MARK: - Validation

    static func validateModel(at url: URL) throws -> ModelInfo {
        var info = clm_model_info_t()
        try checkStatus(clm_model_validate(url.path, &info))
        return ModelInfo(from: info)
    }
}
```

### InferenceSession

```swift
final class InferenceSession {
    private let sessionHandle: clm_session_t
    private var isCancelled = false

    init(context: clm_context_t, model: clm_model_t,
         contextSize: Int, batchSize: Int) throws {
        var params = clm_session_default_params()
        params.context_size = UInt32(contextSize)
        params.batch_size = UInt32(batchSize)

        var session: clm_session_t?
        try checkStatus(clm_session_create(context, model, params, &session))
        self.sessionHandle = session!
    }

    deinit {
        clm_session_destroy(sessionHandle)
    }

    func generate(
        prompt: String,
        parameters: GenerationParameters = .default
    ) -> AsyncThrowingStream<Token, Error> {
        isCancelled = false
        let session = sessionHandle

        return AsyncThrowingStream { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var params = clm_generation_default_params()
                params.temperature = parameters.temperature
                params.top_k = parameters.topK
                params.top_p = parameters.topP
                params.repeat_penalty = parameters.repeatPenalty
                params.max_tokens = parameters.maxTokens
                params.seed = parameters.seed

                // Bridge callback: C function pointer + user_data
                let callbackContext = CallbackContext(continuation: continuation)
                let userDataPtr = Unmanaged.passRetained(callbackContext).toOpaque()

                let status = clm_generate(
                    session,
                    prompt,
                    params,
                    { tokenText, tokenId, userData -> Bool in
                        let ctx = Unmanaged<CallbackContext>.fromOpaque(userData!)
                            .takeUnretainedValue()
                        let text = String(cString: tokenText!)
                        ctx.continuation.yield(Token(id: Int(tokenId), text: text))
                        return true  // continue generation
                    },
                    userDataPtr
                )

                Unmanaged<CallbackContext>.fromOpaque(userDataPtr).release()

                if status == CLM_STATUS_CANCELLED {
                    continuation.finish()
                } else if status != CLM_STATUS_OK {
                    continuation.finish(throwing: CoreLMError.generationFailed(
                        reason: "Generation failed with status \(status)"
                    ))
                } else {
                    continuation.finish()
                }
            }
        }
    }

    func cancel() {
        isCancelled = true
        clm_generate_cancel(sessionHandle)
    }

    func reset() throws {
        try checkStatus(clm_session_reset(sessionHandle))
    }

    func getMetrics() throws -> RuntimeMetrics {
        var metrics = clm_metrics_t()
        try checkStatus(clm_get_metrics(sessionHandle, &metrics))
        return RuntimeMetrics(from: metrics)
    }
}
```

### Supporting Types

```swift
struct Token {
    let id: Int
    let text: String
}

struct ModelInfo {
    let architecture: String
    let name: String
    let quantization: String
    let parameterCount: UInt64
    let fileSizeBytes: UInt64
    let contextLength: Int
    let embeddingLength: Int
    let numLayers: Int
    let numHeads: Int
    let numKVHeads: Int
    let vocabSize: Int
}

struct GenerationParameters {
    var temperature: Float = 0.7
    var topK: Int32 = 40
    var topP: Float = 0.95
    var repeatPenalty: Float = 1.1
    var maxTokens: Int32 = 2048
    var seed: UInt64 = 0

    static let `default` = GenerationParameters()
}

struct RuntimeMetrics {
    let modelLoadTime: TimeInterval
    let promptEvalTime: TimeInterval
    let promptEvalTokens: Int
    let promptEvalSpeed: Double      // tok/s
    let generationTime: TimeInterval
    let generationTokens: Int
    let generationSpeed: Double      // tok/s
    let timeToFirstToken: TimeInterval
    let memoryModel: Int64
    let memoryKVCache: Int64
    let memoryScratch: Int64
    let contextTokensUsed: Int
    let contextTokensMax: Int
    let activeBackend: String

    static let empty = RuntimeMetrics(/* all zeros */)
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

    static func from(status: clm_status_t, context: clm_context_t?) -> CoreLMError {
        let message = context.flatMap { String(cString: clm_get_last_error($0)) } ?? "Unknown"
        switch status {
        case CLM_STATUS_FILE_ERROR:        return .fileError(message)
        case CLM_STATUS_UNSUPPORTED_ARCH:  return .unsupportedArchitecture(message)
        case CLM_STATUS_UNSUPPORTED_QUANT: return .unsupportedQuantization(message)
        case CLM_STATUS_MEMORY_ERROR:      return .memoryAllocationFailed
        case CLM_STATUS_BACKEND_ERROR:     return .backendInitFailed(backend: "unknown", reason: message)
        case CLM_STATUS_CANCELLED:         return .cancelled
        case CLM_STATUS_INVALID_STATE:     return .invalidState(message)
        case CLM_STATUS_MODEL_ERROR:       return .modelLoadFailed(reason: message)
        default:                           return .generationFailed(reason: message)
        }
    }
}

enum Backend: String {
    case auto = "auto"
    case cpu = "cpu"
    case metal = "metal"
}

// Helper
private func checkStatus(_ status: clm_status_t) throws {
    guard status == CLM_STATUS_OK else {
        throw CoreLMError.generationFailed(reason: "Operation failed with status \(status.rawValue)")
    }
}

// Callback bridge helper
private class CallbackContext {
    let continuation: AsyncThrowingStream<Token, Error>.Continuation
    init(continuation: AsyncThrowingStream<Token, Error>.Continuation) {
        self.continuation = continuation
    }
}
```

---

## Usage Example — Full Flow

```swift
// 1. Create runtime
let runtime = try CoreLMRuntime(backend: .auto)

// 2. Load model
try await runtime.loadModel(at: URL(fileURLWithPath: "/Models/llama-3.2-3b-q4_0.gguf"))

// 3. Create session
let session = try runtime.createSession(contextSize: 4096)

// 4. Generate with streaming
for try await token in session.generate(
    prompt: "Explain how attention works in transformers.",
    parameters: .init(temperature: 0.7, maxTokens: 512)
) {
    print(token.text, terminator: "")
}

// 5. Get metrics after generation
let metrics = try session.getMetrics()
print("\nSpeed: \(metrics.generationSpeed) tok/s")

// 6. Cancel (from another thread/task)
session.cancel()

// 7. Cleanup is automatic via deinit
```

---

## Threading Contract

| Operation | Thread | Blocking? |
|-----------|--------|-----------|
| `clm_context_create` | Any | Brief |
| `clm_model_load` | Background | Yes (seconds) |
| `clm_model_unload` | Any | Brief |
| `clm_session_create` | Any | Brief |
| `clm_generate` | Background | Yes (duration of generation) |
| `clm_generate_cancel` | **Any** (thread-safe) | No |
| `clm_get_metrics` | Any | No |
| Token callback | Engine thread | Must return quickly |

The Swift wrapper enforces this contract — `loadModel` and `generate` are dispatched to background queues. `cancel()` is safe to call from the main thread.

---

## ABI Stability Notes

- The C API header is the stability boundary. Internal C++ changes do not affect Swift code.
- Struct fields should only be appended, never reordered (for future binary compatibility).
- New status codes are appended to the enum.
- The engine is compiled as a static library (`libcorelm.a`) linked into the app.
