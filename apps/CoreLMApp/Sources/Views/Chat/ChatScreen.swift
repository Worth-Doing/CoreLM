import SwiftUI

struct ChatScreen: View {
    @Bindable var viewModel: ChatViewModel

    @Environment(ModelRegistry.self) private var modelRegistry

    var body: some View {
        VStack(spacing: 0) {
            // Header
            ChatHeaderBar(
                modelName: modelRegistry.loadedModel?.name ?? "No model",
                quantization: modelRegistry.loadedModel?.quantization
            )

            Divider()

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: Theme.spacingLarge) {
                        ForEach(viewModel.messages) { message in
                            MessageBubbleView(message: message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) {
                    if let lastId = viewModel.messages.last?.id {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input
            VStack(spacing: Theme.spacing) {
                PromptComposerView(
                    text: $viewModel.promptText,
                    canSend: viewModel.canSend,
                    isGenerating: viewModel.isGenerating,
                    onSend: { viewModel.sendMessage() }
                )

                GenerationControlsView(
                    isGenerating: viewModel.isGenerating,
                    hasMessages: !viewModel.messages.isEmpty,
                    onStop: { viewModel.stopGeneration() },
                    onRegenerate: { viewModel.regenerate() },
                    onClear: { viewModel.clearContext() }
                )
            }
            .padding()
        }
    }
}

struct ChatHeaderBar: View {
    let modelName: String
    let quantization: String?

    var body: some View {
        HStack {
            Image(systemName: "cube")
                .foregroundStyle(Theme.secondaryText)

            Text(modelName)
                .font(Theme.headlineFont)

            if let quant = quantization {
                Text(quant)
                    .font(Theme.captionFont)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.badgeColor(for: quant).opacity(0.2))
                    .foregroundStyle(Theme.badgeColor(for: quant))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, Theme.spacing)
    }
}

struct GenerationControlsView: View {
    let isGenerating: Bool
    let hasMessages: Bool
    let onStop: () -> Void
    let onRegenerate: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: Theme.spacing) {
            if isGenerating {
                Button(action: onStop) {
                    Label("Stop", systemImage: "stop.circle")
                }
                .keyboardShortcut(".", modifiers: .command)
            }

            if hasMessages && !isGenerating {
                Button(action: onRegenerate) {
                    Label("Regenerate", systemImage: "arrow.counterclockwise")
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button(action: onClear) {
                    Label("Clear", systemImage: "trash")
                }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
            }

            Spacer()
        }
        .buttonStyle(.borderless)
        .font(Theme.captionFont)
        .foregroundStyle(Theme.secondaryText)
    }
}
