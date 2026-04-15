import Foundation

// MARK: - Ollama Models

struct OllamaModel: Identifiable, Codable, Hashable {
    var id: String { name }
    let name: String
    let modifiedAt: String?
    let size: Int64?
    let digest: String?
    let details: OllamaModelDetails?

    enum CodingKeys: String, CodingKey {
        case name
        case modifiedAt = "modified_at"
        case size
        case digest
        case details
    }

    var sizeFormatted: String {
        guard let size = size else { return "Unknown" }
        let gb = Double(size) / 1_073_741_824.0
        if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(size) / 1_048_576.0
        return String(format: "%.0f MB", mb)
    }
}

struct OllamaModelDetails: Codable, Hashable {
    let format: String?
    let family: String?
    let parameterSize: String?
    let quantizationLevel: String?

    enum CodingKeys: String, CodingKey {
        case format
        case family
        case parameterSize = "parameter_size"
        case quantizationLevel = "quantization_level"
    }
}

struct OllamaModelList: Codable {
    let models: [OllamaModel]
}

// MARK: - Ollama Chat

struct OllamaChatRequest: Codable {
    let model: String
    let messages: [OllamaChatMessage]
    let stream: Bool
    let options: OllamaOptions?
}

struct OllamaChatMessage: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    let role: String
    let content: String

    enum CodingKeys: String, CodingKey {
        case role, content
    }
}

struct OllamaOptions: Codable {
    let temperature: Double?
    let topP: Double?
    let topK: Int?
    let numCtx: Int?
    let seed: Int?
    let repeatPenalty: Double?

    enum CodingKeys: String, CodingKey {
        case temperature
        case topP = "top_p"
        case topK = "top_k"
        case numCtx = "num_ctx"
        case seed
        case repeatPenalty = "repeat_penalty"
    }
}

struct OllamaChatResponse: Codable {
    let model: String?
    let message: OllamaChatMessage?
    let done: Bool
    let totalDuration: Int64?
    let loadDuration: Int64?
    let promptEvalCount: Int?
    let evalCount: Int?
    let evalDuration: Int64?

    enum CodingKeys: String, CodingKey {
        case model, message, done
        case totalDuration = "total_duration"
        case loadDuration = "load_duration"
        case promptEvalCount = "prompt_eval_count"
        case evalCount = "eval_count"
        case evalDuration = "eval_duration"
    }

    var tokensPerSecond: Double? {
        guard let evalCount = evalCount, let evalDuration = evalDuration, evalDuration > 0 else {
            return nil
        }
        return Double(evalCount) / (Double(evalDuration) / 1_000_000_000.0)
    }
}

struct OllamaPullResponse: Codable {
    let status: String
    let digest: String?
    let total: Int64?
    let completed: Int64?

    var progress: Double? {
        guard let total = total, let completed = completed, total > 0 else { return nil }
        return Double(completed) / Double(total)
    }
}

// MARK: - Hugging Face Models

struct HFModel: Identifiable, Codable, Hashable {
    var id: String { modelId }
    let modelId: String
    let author: String?
    let sha: String?
    let lastModified: String?
    let tags: [String]?
    let downloads: Int?
    let likes: Int?
    let pipelineTag: String?

    enum CodingKeys: String, CodingKey {
        case modelId
        case author
        case sha
        case lastModified
        case tags
        case downloads
        case likes
        case pipelineTag = "pipeline_tag"
    }

    var downloadsFormatted: String {
        guard let downloads = downloads else { return "N/A" }
        if downloads >= 1_000_000 {
            return String(format: "%.1fM", Double(downloads) / 1_000_000.0)
        }
        if downloads >= 1_000 {
            return String(format: "%.1fK", Double(downloads) / 1_000.0)
        }
        return "\(downloads)"
    }

    var isGGUF: Bool {
        tags?.contains("gguf") ?? false
    }
}

struct HFModelDetail: Codable {
    let modelId: String?
    let author: String?
    let tags: [String]?
    let downloads: Int?
    let likes: Int?
    let cardData: HFCardData?
    let siblings: [HFSibling]?

    enum CodingKeys: String, CodingKey {
        case modelId
        case author
        case tags
        case downloads
        case likes
        case cardData = "cardData"
        case siblings
    }
}

struct HFCardData: Codable {
    let license: String?
    let language: [String]?
}

struct HFSibling: Codable, Identifiable, Hashable {
    var id: String { rfilename }
    let rfilename: String

    var isGGUF: Bool {
        rfilename.lowercased().hasSuffix(".gguf")
    }

    var isSafetensors: Bool {
        rfilename.hasSuffix(".safetensors")
    }

    var isPyTorch: Bool {
        rfilename.hasSuffix(".bin") || rfilename.hasSuffix(".pt")
    }

    var formatLabel: String {
        if isGGUF { return "GGUF" }
        if isSafetensors { return "Safetensors" }
        if isPyTorch { return "PyTorch" }
        return "Other"
    }

    var isModelFile: Bool {
        isGGUF || isSafetensors || isPyTorch
    }

    /// Extract quantization type from GGUF filename
    /// e.g. "model-Q4_K_M.gguf" -> "Q4_K_M"
    var quantizationType: String? {
        guard isGGUF else { return nil }
        let name = rfilename
            .replacingOccurrences(of: ".gguf", with: "", options: .caseInsensitive)

        // Common patterns: Q4_K_M, Q5_K_S, Q8_0, IQ4_XS, Q2_K, Q6_K, Q3_K_L, F16, F32, etc.
        let patterns = [
            "IQ1_S", "IQ1_M",
            "IQ2_XXS", "IQ2_XS", "IQ2_S", "IQ2_M",
            "IQ3_XXS", "IQ3_XS", "IQ3_S", "IQ3_M",
            "IQ4_XS", "IQ4_NL",
            "Q2_K", "Q2_K_S",
            "Q3_K_S", "Q3_K_M", "Q3_K_L", "Q3_K",
            "Q4_0", "Q4_1", "Q4_K_S", "Q4_K_M", "Q4_K", "Q4_0_4_4", "Q4_0_4_8", "Q4_0_8_8",
            "Q5_0", "Q5_1", "Q5_K_S", "Q5_K_M", "Q5_K",
            "Q6_K",
            "Q8_0", "Q8_1", "Q8_K",
            "F16", "F32", "BF16",
        ]
        let upperName = name.uppercased()
        // Match longest pattern first
        for pattern in patterns.sorted(by: { $0.count > $1.count }) {
            if upperName.contains(pattern) {
                return pattern
            }
        }
        return nil
    }

    /// Human-readable quality rating for the quantization
    var quantizationQuality: QuantQuality {
        guard let q = quantizationType else { return .unknown }
        switch q {
        case "F32": return .lossless
        case "F16", "BF16": return .lossless
        case "Q8_0", "Q8_1", "Q8_K": return .excellent
        case "Q6_K": return .veryGood
        case "Q5_K_M", "Q5_K", "Q5_1", "Q5_0", "Q5_K_S": return .good
        case "Q4_K_M", "Q4_K", "Q4_1": return .recommended
        case "Q4_K_S", "Q4_0", "Q4_0_4_4", "Q4_0_4_8", "Q4_0_8_8": return .decent
        case "Q3_K_L": return .decent
        case "Q3_K_M", "Q3_K", "Q3_K_S": return .small
        case "Q2_K", "Q2_K_S": return .tiny
        default:
            if q.hasPrefix("IQ") { return .small }
            return .unknown
        }
    }

    /// Estimated model size tier from filename
    var modelSizeTier: String? {
        let name = rfilename.lowercased()
        let sizePatterns = ["1b", "1.5b", "2b", "3b", "4b", "7b", "8b", "13b", "14b", "27b", "32b", "34b", "70b", "72b", "405b"]
        for size in sizePatterns.reversed() {
            if name.contains(size) || name.contains("-\(size)") || name.contains("_\(size)") {
                return size.uppercased()
            }
        }
        return nil
    }
}

enum QuantQuality: String {
    case lossless = "Lossless"
    case excellent = "Excellent"
    case veryGood = "Very Good"
    case good = "Good"
    case recommended = "Recommended"
    case decent = "Decent"
    case small = "Small"
    case tiny = "Tiny"
    case unknown = ""

    var color: String {
        switch self {
        case .lossless, .excellent: return "green"
        case .veryGood, .good: return "blue"
        case .recommended: return "purple"
        case .decent: return "orange"
        case .small, .tiny: return "red"
        case .unknown: return "gray"
        }
    }
}

// MARK: - Chat Models

struct Conversation: Identifiable, Codable {
    let id: UUID
    var title: String
    var modelName: String
    var messages: [ChatMessage]
    var systemPrompt: String
    var createdAt: Date
    var updatedAt: Date
    var parameters: ChatParameters

    init(
        id: UUID = UUID(),
        title: String = "New Chat",
        modelName: String = "",
        messages: [ChatMessage] = [],
        systemPrompt: String = "You are a helpful assistant.",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        parameters: ChatParameters = ChatParameters()
    ) {
        self.id = id
        self.title = title
        self.modelName = modelName
        self.messages = messages
        self.systemPrompt = systemPrompt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.parameters = parameters
    }
}

struct ChatMessage: Identifiable, Codable, Hashable {
    let id: UUID
    let role: MessageRole
    var content: String
    let timestamp: Date
    var isStreaming: Bool

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        isStreaming: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isStreaming = isStreaming
    }

    func toOllamaMessage() -> OllamaChatMessage {
        OllamaChatMessage(role: role.rawValue, content: content)
    }
}

enum MessageRole: String, Codable, Hashable {
    case system
    case user
    case assistant
}

struct ChatParameters: Codable {
    var temperature: Double = 0.7
    var topP: Double = 0.9
    var topK: Int = 40
    var contextLength: Int = 4096
    var repeatPenalty: Double = 1.1
    var seed: Int? = nil

    func toOllamaOptions() -> OllamaOptions {
        OllamaOptions(
            temperature: temperature,
            topP: topP,
            topK: topK,
            numCtx: contextLength,
            seed: seed,
            repeatPenalty: repeatPenalty
        )
    }
}

// MARK: - Download Models

struct DownloadTask: Identifiable {
    let id: UUID
    let modelId: String
    let fileName: String
    let url: URL
    var progress: Double
    var downloadedBytes: Int64
    var totalBytes: Int64
    var state: DownloadState
    var error: String?

    var progressFormatted: String {
        String(format: "%.1f%%", progress * 100)
    }

    var downloadedFormatted: String {
        ByteCountFormatter.string(fromByteCount: downloadedBytes, countStyle: .file)
    }

    var totalFormatted: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
}

enum DownloadState: String {
    case pending
    case downloading
    case paused
    case completed
    case failed
    case cancelled
}

// MARK: - System Monitoring

struct SystemMetrics {
    var cpuUsage: Double = 0
    var memoryUsed: UInt64 = 0
    var memoryTotal: UInt64 = 0
    var gpuUsage: Double = 0
    var gpuMemoryUsed: UInt64 = 0
    var gpuMemoryTotal: UInt64 = 0

    var memoryUsedGB: Double {
        Double(memoryUsed) / 1_073_741_824.0
    }

    var memoryTotalGB: Double {
        Double(memoryTotal) / 1_073_741_824.0
    }

    var memoryUsagePercent: Double {
        guard memoryTotal > 0 else { return 0 }
        return Double(memoryUsed) / Double(memoryTotal) * 100
    }
}

// MARK: - API Models (OpenAI-compatible)

struct OpenAIChatRequest: Codable {
    let model: String
    let messages: [OpenAIChatMessage]
    let temperature: Double?
    let stream: Bool?
    let maxTokens: Int?

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream
        case maxTokens = "max_tokens"
    }
}

struct OpenAIChatMessage: Codable {
    let role: String
    let content: String
}

struct OpenAIChatResponse: Codable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [OpenAIChoice]
    let usage: OpenAIUsage?
}

struct OpenAIChoice: Codable {
    let index: Int
    let message: OpenAIChatMessage?
    let delta: OpenAIChatMessage?
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case index, message, delta
        case finishReason = "finish_reason"
    }
}

struct OpenAIUsage: Codable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

struct OpenAIModelList: Codable {
    let object: String
    let data: [OpenAIModelEntry]
}

struct OpenAIModelEntry: Codable {
    let id: String
    let object: String
    let created: Int
    let ownedBy: String

    enum CodingKeys: String, CodingKey {
        case id, object, created
        case ownedBy = "owned_by"
    }
}

// MARK: - Prompt Template

struct PromptTemplate: Identifiable, Codable {
    let id: UUID
    var name: String
    var systemPrompt: String
    var parameters: ChatParameters
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        systemPrompt: String = "You are a helpful assistant.",
        parameters: ChatParameters = ChatParameters(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.systemPrompt = systemPrompt
        self.parameters = parameters
        self.createdAt = createdAt
    }
}
