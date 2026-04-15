import SwiftUI

struct DiagnosticsScreen: View {
    var viewModel: DiagnosticsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacingXL) {
                Text("Diagnostics")
                    .font(Theme.titleFont)
                    .padding(.horizontal)

                // Runtime Status
                DiagnosticsSection(title: "Runtime Status") {
                    DiagnosticsRow(label: "State", value: viewModel.runtimeState)
                    DiagnosticsRow(label: "Model", value: viewModel.loadedModelName)
                    DiagnosticsRow(label: "Backend", value: viewModel.backendName)
                }

                // Performance
                DiagnosticsSection(title: "Performance") {
                    DiagnosticsRow(
                        label: "Load Time",
                        value: viewModel.hasMetrics ? String(format: "%.1f ms", viewModel.metrics.modelLoadTime * 1000) : "—"
                    )
                    DiagnosticsRow(
                        label: "Prompt Eval",
                        value: viewModel.hasMetrics ? String(format: "%.1f tok/s", viewModel.metrics.promptEvalSpeed) : "—"
                    )
                    DiagnosticsRow(
                        label: "Generation",
                        value: viewModel.hasMetrics ? String(format: "%.1f tok/s", viewModel.metrics.generationSpeed) : "—"
                    )
                    DiagnosticsRow(
                        label: "First Token",
                        value: viewModel.hasMetrics ? String(format: "%.0f ms", viewModel.metrics.timeToFirstToken * 1000) : "—"
                    )
                }

                // Memory
                DiagnosticsSection(title: "Memory") {
                    DiagnosticsRow(label: "Model", value: viewModel.hasMetrics ? viewModel.metrics.memoryModelFormatted : "—")
                    DiagnosticsRow(label: "KV Cache", value: viewModel.hasMetrics ? viewModel.metrics.memoryKVCacheFormatted : "—")
                    DiagnosticsRow(label: "Scratch", value: viewModel.hasMetrics ? viewModel.metrics.memoryScratchFormatted : "—")
                    DiagnosticsRow(label: "Total", value: viewModel.hasMetrics ? viewModel.metrics.memoryTotalFormatted : "—")
                }

                // Context
                DiagnosticsSection(title: "Context") {
                    DiagnosticsRow(
                        label: "Tokens",
                        value: viewModel.hasMetrics
                            ? "\(viewModel.metrics.contextTokensUsed) / \(viewModel.metrics.contextTokensMax)"
                            : "—"
                    )
                    DiagnosticsRow(
                        label: "Utilization",
                        value: viewModel.hasMetrics
                            ? String(format: "%.0f%%", viewModel.metrics.contextUtilization * 100)
                            : "—"
                    )
                }
            }
            .padding()
        }
    }
}

struct DiagnosticsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            Text(title)
                .font(Theme.headlineFont)
                .foregroundStyle(Theme.secondaryText)

            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .fill(Theme.secondaryBackground)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        }
    }
}

struct DiagnosticsRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.secondaryText)
            Spacer()
            Text(value)
                .font(Theme.monoFont)
                .foregroundStyle(Theme.text)
        }
        .padding(.horizontal, Theme.spacingLarge)
        .padding(.vertical, Theme.spacing)
    }
}
