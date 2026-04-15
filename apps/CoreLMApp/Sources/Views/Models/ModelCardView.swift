import SwiftUI

struct ModelCardView: View {
    let model: ModelInfo
    let isLoaded: Bool
    let isLoading: Bool
    let onLoad: () -> Void
    let onUnload: () -> Void
    let onRemove: () -> Void
    let onShowInFinder: () -> Void

    var body: some View {
        HStack(spacing: Theme.spacingLarge) {
            // Status indicator
            Circle()
                .fill(isLoaded ? Theme.success : Theme.separator)
                .frame(width: 10, height: 10)

            // Model info
            VStack(alignment: .leading, spacing: Theme.spacingSmall) {
                HStack(spacing: Theme.spacing) {
                    Text(model.name)
                        .font(Theme.headlineFont)
                        .lineLimit(1)

                    Text(model.quantization)
                        .font(Theme.captionFont)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.badgeColor(for: model.quantization).opacity(0.15))
                        .foregroundStyle(Theme.badgeColor(for: model.quantization))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall))

                    Text(model.architecture)
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.tertiaryText)
                }

                HStack(spacing: Theme.spacingLarge) {
                    Label(model.fileSizeFormatted, systemImage: "doc")
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.secondaryText)

                    if model.parameterCount > 0 {
                        Label(model.parameterCountFormatted, systemImage: "number")
                            .font(Theme.captionFont)
                            .foregroundStyle(Theme.secondaryText)
                    }

                    if let lastLoaded = model.lastLoadedAt {
                        Label(lastLoaded.formatted(.relative(presentation: .named)), systemImage: "clock")
                            .font(Theme.captionFont)
                            .foregroundStyle(Theme.tertiaryText)
                    }
                }
            }

            Spacer()

            // Actions
            if isLoaded {
                Button("Unload", action: onUnload)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                Button("Load", action: onLoad)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isLoading)
            }
        }
        .padding(Theme.spacingLarge)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .fill(Theme.secondaryBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .stroke(isLoaded ? Theme.success.opacity(0.3) : Theme.separator.opacity(0.3), lineWidth: 1)
        )
        .contextMenu {
            Button("Show in Finder", action: onShowInFinder)
            Divider()
            Button("Remove from Registry", role: .destructive, action: onRemove)
        }
    }
}
