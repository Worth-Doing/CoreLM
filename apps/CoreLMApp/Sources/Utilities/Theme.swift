import SwiftUI

enum Theme {
    // MARK: - Colors

    static let background = Color(nsColor: .windowBackgroundColor)
    static let secondaryBackground = Color(nsColor: .controlBackgroundColor)
    static let tertiaryBackground = Color(nsColor: .underPageBackgroundColor)

    static let text = Color(nsColor: .labelColor)
    static let secondaryText = Color(nsColor: .secondaryLabelColor)
    static let tertiaryText = Color(nsColor: .tertiaryLabelColor)

    static let accent = Color.accentColor
    static let separator = Color(nsColor: .separatorColor)

    static let userBubble = Color.accentColor.opacity(0.12)
    static let assistantBubble = Color(nsColor: .controlBackgroundColor)

    static let success = Color.green
    static let warning = Color.orange
    static let error = Color.red

    // MARK: - Typography

    static let titleFont = Font.system(size: 20, weight: .semibold)
    static let headlineFont = Font.system(size: 15, weight: .semibold)
    static let bodyFont = Font.system(size: 14, weight: .regular)
    static let captionFont = Font.system(size: 12, weight: .regular)
    static let monoFont = Font.system(size: 13, weight: .regular, design: .monospaced)
    static let smallMonoFont = Font.system(size: 11, weight: .regular, design: .monospaced)

    // MARK: - Spacing

    static let spacing: CGFloat = 8
    static let spacingSmall: CGFloat = 4
    static let spacingLarge: CGFloat = 16
    static let spacingXL: CGFloat = 24

    // MARK: - Dimensions

    static let sidebarWidth: CGFloat = 220
    static let inspectorWidth: CGFloat = 280
    static let bottomPanelHeight: CGFloat = 200
    static let cornerRadius: CGFloat = 8
    static let cornerRadiusSmall: CGFloat = 4

    // MARK: - Badges

    static func badgeColor(for quantization: String) -> Color {
        switch quantization.uppercased() {
        case "Q4_0": return .blue
        case "Q4_K_M": return .purple
        case "Q8_0": return .green
        case "F16": return .orange
        default: return .gray
        }
    }

    static func statusColor(loaded: Bool) -> Color {
        loaded ? .green : .secondary
    }
}
