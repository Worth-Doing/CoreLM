import SwiftUI

struct RuntimeInspector: View {
    var viewModel: DiagnosticsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacingXL) {
                InspectorSection(title: "Runtime") {
                    InspectorRow(label: "State", value: viewModel.runtimeState)
                    InspectorRow(label: "Model", value: viewModel.loadedModelName)
                    InspectorRow(label: "Backend", value: viewModel.backendName)
                }

                if viewModel.hasMetrics {
                    InspectorSection(title: "Speed") {
                        InspectorRow(label: "Prompt", value: String(format: "%.1f tok/s", viewModel.metrics.promptEvalSpeed))
                        InspectorRow(label: "Generate", value: String(format: "%.1f tok/s", viewModel.metrics.generationSpeed))
                    }

                    InspectorSection(title: "Memory") {
                        InspectorRow(label: "Total", value: viewModel.metrics.memoryTotalFormatted)
                    }
                }
            }
            .padding()
        }
    }
}
