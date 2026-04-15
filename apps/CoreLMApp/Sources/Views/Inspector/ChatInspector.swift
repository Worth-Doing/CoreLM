import SwiftUI

struct ChatInspector: View {
    var viewModel: ChatViewModel
    var modelRegistry: ModelRegistry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacingXL) {
                // Session info
                InspectorSection(title: "Session") {
                    InspectorRow(label: "Model", value: modelRegistry.loadedModel?.name ?? "None")
                    InspectorRow(label: "Backend", value: viewModel.metrics.activeBackend.isEmpty ? "—" : viewModel.metrics.activeBackend)
                    InspectorRow(
                        label: "Context",
                        value: viewModel.metrics.contextTokensMax > 0
                            ? "\(viewModel.metrics.contextTokensUsed) / \(viewModel.metrics.contextTokensMax)"
                            : "—"
                    )
                }

                // Generation params (from settings, read-only display)
                InspectorSection(title: "Generation") {
                    InspectorRow(label: "Status", value: statusText)
                }

                // Last run metrics
                if viewModel.metrics.generationTokens > 0 {
                    InspectorSection(title: "Last Run") {
                        InspectorRow(label: "Tokens", value: "\(viewModel.metrics.generationTokens)")
                        InspectorRow(label: "Speed", value: String(format: "%.1f tok/s", viewModel.metrics.generationSpeed))
                        InspectorRow(label: "Duration", value: String(format: "%.1fs", viewModel.metrics.generationTime))
                    }
                }

                // Memory
                if viewModel.metrics.memoryModel > 0 {
                    InspectorSection(title: "Memory") {
                        InspectorRow(label: "Model", value: viewModel.metrics.memoryModelFormatted)
                        InspectorRow(label: "Cache", value: viewModel.metrics.memoryKVCacheFormatted)
                    }
                }
            }
            .padding()
        }
    }

    private var statusText: String {
        switch viewModel.generationState {
        case .idle: return "Idle"
        case .generating: return "Generating..."
        case .cancelled: return "Cancelled"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}

// MARK: - Inspector Components

struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSmall) {
            Text(title)
                .font(Theme.captionFont)
                .foregroundStyle(Theme.tertiaryText)
                .textCase(.uppercase)

            VStack(spacing: 0) {
                content()
            }
        }
    }
}

struct InspectorRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(Theme.captionFont)
                .foregroundStyle(Theme.secondaryText)
            Spacer()
            Text(value)
                .font(Theme.smallMonoFont)
                .foregroundStyle(Theme.text)
        }
        .padding(.vertical, 3)
    }
}
