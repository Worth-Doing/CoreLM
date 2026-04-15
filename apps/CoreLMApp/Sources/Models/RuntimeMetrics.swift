import Foundation

struct RuntimeMetrics {
    var modelLoadTime: TimeInterval = 0
    var promptEvalTime: TimeInterval = 0
    var promptEvalTokens: Int = 0
    var promptEvalSpeed: Double = 0
    var generationTime: TimeInterval = 0
    var generationTokens: Int = 0
    var generationSpeed: Double = 0
    var timeToFirstToken: TimeInterval = 0
    var memoryModel: Int64 = 0
    var memoryKVCache: Int64 = 0
    var memoryScratch: Int64 = 0
    var contextTokensUsed: Int = 0
    var contextTokensMax: Int = 0
    var activeBackend: String = "None"

    var memoryModelFormatted: String { formatBytes(memoryModel) }
    var memoryKVCacheFormatted: String { formatBytes(memoryKVCache) }
    var memoryScratchFormatted: String { formatBytes(memoryScratch) }

    var memoryTotalBytes: Int64 { memoryModel + memoryKVCache + memoryScratch }
    var memoryTotalFormatted: String { formatBytes(memoryTotalBytes) }

    var contextUtilization: Double {
        guard contextTokensMax > 0 else { return 0 }
        return Double(contextTokensUsed) / Double(contextTokensMax)
    }

    static let empty = RuntimeMetrics()

    private func formatBytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1.0 { return String(format: "%.1f GB", gb) }
        let mb = Double(bytes) / 1_048_576
        if mb >= 1.0 { return String(format: "%.0f MB", mb) }
        let kb = Double(bytes) / 1024
        return String(format: "%.0f KB", kb)
    }
}
