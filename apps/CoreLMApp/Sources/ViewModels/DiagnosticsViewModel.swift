import Foundation
import SwiftUI

@Observable
final class DiagnosticsViewModel {
    private let modelRegistry: ModelRegistry
    private let runtime: CoreLMRuntime

    init(modelRegistry: ModelRegistry, runtime: CoreLMRuntime) {
        self.modelRegistry = modelRegistry
        self.runtime = runtime
    }

    var metrics: RuntimeMetrics {
        runtime.metrics
    }

    var runtimeState: String {
        switch runtime.state {
        case .idle: return "Idle"
        case .loading: return "Loading..."
        case .ready: return "Ready"
        case .generating: return "Generating"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    var loadedModelName: String {
        runtime.loadedModelInfo?.name ?? modelRegistry.loadedModel?.name ?? "None"
    }

    var backendName: String {
        let b = metrics.activeBackend
        return b.isEmpty || b == "None" ? "CPU (Accelerate)" : b
    }

    var hasMetrics: Bool {
        metrics.generationTokens > 0 || metrics.promptEvalTokens > 0
    }
}
