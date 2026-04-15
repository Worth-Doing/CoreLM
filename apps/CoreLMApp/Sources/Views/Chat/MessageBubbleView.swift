import SwiftUI

struct MessageBubbleView: View {
    let message: Message

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: Theme.spacingLarge) {
            // Role icon
            roleIcon
                .frame(width: 28, height: 28)

            // Content
            VStack(alignment: .leading, spacing: Theme.spacingSmall) {
                Text(message.role == .user ? "You" : "Assistant")
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.secondaryText)

                Text(message.content)
                    .font(Theme.bodyFont)
                    .textSelection(.enabled)
                    .lineSpacing(4)

                if isHovering {
                    HStack(spacing: Theme.spacing) {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(message.content, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Theme.tertiaryText)

                        Text(message.timestamp, style: .time)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.tertiaryText)
                    }
                }
            }

            Spacer(minLength: 40)
        }
        .padding(.horizontal, Theme.spacingLarge)
        .padding(.vertical, Theme.spacing)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .fill(message.role == .user ? Theme.userBubble : Color.clear)
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }

    @ViewBuilder
    private var roleIcon: some View {
        switch message.role {
        case .user:
            Image(systemName: "person.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Theme.accent)
        case .assistant:
            Image(systemName: "cpu")
                .font(.system(size: 18))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 22, height: 22)
        case .system:
            Image(systemName: "gearshape")
                .font(.system(size: 18))
                .foregroundStyle(Theme.tertiaryText)
                .frame(width: 22, height: 22)
        }
    }
}
