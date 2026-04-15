import Foundation

struct ModelInfo: Identifiable, Codable {
    let id: UUID
    var name: String
    var architecture: String
    var quantization: String
    var parameterCount: UInt64
    var fileSizeBytes: UInt64
    var contextLength: Int
    var embeddingLength: Int
    var numLayers: Int
    var numHeads: Int
    var numKVHeads: Int
    var vocabSize: Int
    var filePath: String
    var addedAt: Date
    var lastLoadedAt: Date?

    var fileSizeFormatted: String {
        let gb = Double(fileSizeBytes) / 1_073_741_824
        if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(fileSizeBytes) / 1_048_576
        return String(format: "%.0f MB", mb)
    }

    var parameterCountFormatted: String {
        let b = Double(parameterCount) / 1_000_000_000
        if b >= 1.0 {
            return String(format: "%.1fB", b)
        }
        let m = Double(parameterCount) / 1_000_000
        return String(format: "%.0fM", m)
    }
}
