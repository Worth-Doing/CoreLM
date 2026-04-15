import SwiftUI

struct ModelInspector: View {
    let model: ModelInfo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacingXL) {
                // Header
                VStack(alignment: .leading, spacing: Theme.spacingSmall) {
                    Text(model.name)
                        .font(Theme.headlineFont)

                    HStack(spacing: Theme.spacing) {
                        Text(model.quantization)
                            .font(Theme.captionFont)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.badgeColor(for: model.quantization).opacity(0.15))
                            .foregroundStyle(Theme.badgeColor(for: model.quantization))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))

                        Text(model.fileSizeFormatted)
                            .font(Theme.captionFont)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }

                // Architecture
                InspectorSection(title: "Architecture") {
                    InspectorRow(label: "Type", value: model.architecture)
                    if model.parameterCount > 0 {
                        InspectorRow(label: "Parameters", value: model.parameterCountFormatted)
                    }
                    if model.numLayers > 0 {
                        InspectorRow(label: "Layers", value: "\(model.numLayers)")
                    }
                    if model.numHeads > 0 {
                        InspectorRow(label: "Heads", value: "\(model.numHeads)")
                    }
                    if model.numKVHeads > 0 {
                        InspectorRow(label: "KV Heads", value: "\(model.numKVHeads)")
                    }
                    if model.embeddingLength > 0 {
                        InspectorRow(label: "Hidden Size", value: "\(model.embeddingLength)")
                    }
                    if model.contextLength > 0 {
                        InspectorRow(label: "Context", value: "\(model.contextLength)")
                    }
                }

                // Quantization
                InspectorSection(title: "Quantization") {
                    InspectorRow(label: "Type", value: model.quantization)
                    InspectorRow(label: "File Size", value: model.fileSizeFormatted)
                }

                // Tokenizer
                if model.vocabSize > 0 {
                    InspectorSection(title: "Tokenizer") {
                        InspectorRow(label: "Type", value: "BPE")
                        InspectorRow(label: "Vocab Size", value: "\(model.vocabSize)")
                    }
                }

                // File
                InspectorSection(title: "File") {
                    InspectorRow(label: "Added", value: model.addedAt.formatted(date: .abbreviated, time: .omitted))
                    if let lastLoaded = model.lastLoadedAt {
                        InspectorRow(label: "Last Loaded", value: lastLoaded.formatted(.relative(presentation: .named)))
                    }
                }

                // Path (truncated)
                VStack(alignment: .leading, spacing: Theme.spacingSmall) {
                    Text("PATH")
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.tertiaryText)

                    Text(model.filePath)
                        .font(Theme.smallMonoFont)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
            }
            .padding()
        }
    }
}
