import Foundation
import SwiftUI

@Observable
final class DiagnosticsViewModel {
    var metrics: RuntimeMetrics = .empty

    private let modelRegistry: ModelRegistry

    init(modelRegistry: ModelRegistry) {
        self.modelRegistry = modelRegistry
    }

    var runtimeState: String {
        if modelRegistry.loadedModelId != nil {
            return "Ready"
        }
        return "Idle"
    }

    var loadedModelName: String {
        modelRegistry.loadedModel?.name ?? "None"
    }

    var backendName: String {
        metrics.activeBackend.isEmpty ? "None" : metrics.activeBackend
    }

    // Phase 3+: These will be populated by the runtime bridge
    var hasMetrics: Bool {
        metrics.generationTokens > 0
    }
}
