import Foundation

struct GenerationPreset: Identifiable, Codable {
    let id: UUID
    var name: String
    var icon: String
    var parameters: GenerationParameters

    static let builtIn: [GenerationPreset] = [
        GenerationPreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Balanced",
            icon: "scale.3d",
            parameters: GenerationParameters(
                temperature: 0.7,
                topK: 40,
                topP: 0.95,
                repeatPenalty: 1.1,
                maxTokens: 2048,
                seed: 0
            )
        ),
        GenerationPreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "Creative",
            icon: "paintbrush",
            parameters: GenerationParameters(
                temperature: 1.0,
                topK: 80,
                topP: 0.98,
                repeatPenalty: 1.05,
                maxTokens: 4096,
                seed: 0
            )
        ),
        GenerationPreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            name: "Precise",
            icon: "scope",
            parameters: GenerationParameters(
                temperature: 0.3,
                topK: 20,
                topP: 0.85,
                repeatPenalty: 1.15,
                maxTokens: 2048,
                seed: 0
            )
        ),
        GenerationPreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            name: "Code",
            icon: "chevron.left.forwardslash.chevron.right",
            parameters: GenerationParameters(
                temperature: 0.2,
                topK: 10,
                topP: 0.9,
                repeatPenalty: 1.0,
                maxTokens: 4096,
                seed: 0
            )
        ),
        GenerationPreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
            name: "Deterministic",
            icon: "lock",
            parameters: GenerationParameters(
                temperature: 0.0,
                topK: 1,
                topP: 1.0,
                repeatPenalty: 1.0,
                maxTokens: 2048,
                seed: 42
            )
        ),
    ]
}
