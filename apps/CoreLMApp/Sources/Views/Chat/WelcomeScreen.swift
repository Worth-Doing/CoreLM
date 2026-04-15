import SwiftUI

struct WelcomeScreen: View {
    let onNewChat: () -> Void
    let onImportModel: () -> Void

    @Environment(ModelRegistry.self) private var modelRegistry

    var body: some View {
        VStack(spacing: Theme.spacingXL) {
            Spacer()

            // Logo area
            VStack(spacing: Theme.spacingLarge) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 64))
                    .foregroundStyle(Theme.accent.opacity(0.6))

                Text("CoreLM")
                    .font(.system(size: 32, weight: .bold))

                Text("Local AI, native to your Mac")
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.secondaryText)
            }

            // Actions
            VStack(spacing: Theme.spacingLarge) {
                if modelRegistry.loadedModel != nil {
                    Button(action: onNewChat) {
                        Label("New Chat", systemImage: "plus.bubble")
                            .frame(width: 200)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                } else if !modelRegistry.models.isEmpty {
                    Text("Load a model to start chatting")
                        .font(Theme.bodyFont)
                        .foregroundStyle(Theme.secondaryText)

                    Button(action: onImportModel) {
                        Label("Go to Models", systemImage: "cube")
                            .frame(width: 200)
                    }
                    .controlSize(.large)
                    .buttonStyle(.bordered)
                } else {
                    Text("Import a model to get started")
                        .font(Theme.bodyFont)
                        .foregroundStyle(Theme.secondaryText)

                    Button(action: onImportModel) {
                        Label("Import Model", systemImage: "square.and.arrow.down")
                            .frame(width: 200)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                }
            }

            Spacer()

            // Hints
            VStack(spacing: Theme.spacingSmall) {
                Text("Supported format: GGUF (Q4_0)")
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.tertiaryText)

                Text("Recommended: LLaMA 3.2 1B or 3B for best experience")
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.tertiaryText)
            }
            .padding(.bottom, Theme.spacingXL)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
