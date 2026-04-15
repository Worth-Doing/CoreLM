import Foundation

struct GenerationParameters: Codable {
    var temperature: Float
    var topK: Int
    var topP: Float
    var repeatPenalty: Float
    var maxTokens: Int
    var seed: UInt64

    static let `default` = GenerationParameters(
        temperature: 0.7,
        topK: 40,
        topP: 0.95,
        repeatPenalty: 1.1,
        maxTokens: 2048,
        seed: 0
    )
}
