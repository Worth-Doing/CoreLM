import SwiftUI

// MARK: - Color Theme (Light-first, clean & modern)

extension Color {
    // Brand — worthdoing identity
    static let wdBrand = Color(red: 0.22, green: 0.42, blue: 0.95)      // #3A6CF3 vivid blue
    static let wdBrandLight = Color(red: 0.36, green: 0.54, blue: 0.98) // lighter brand
    static let wdAccent = Color(red: 0.18, green: 0.80, blue: 0.62)     // #2ECC9E teal green
    static let wdSecondary = Color(red: 0.45, green: 0.30, blue: 0.90)  // purple accent

    // Surfaces — light, clean, airy
    static let coreSurface = Color(nsColor: .windowBackgroundColor)
    static let coreSurfaceLight = Color(nsColor: .controlBackgroundColor)
    static let coreSurfaceHover = Color.black.opacity(0.04)
    static let coreSurfaceCard = Color.white
    static let coreSidebar = Color(red: 0.96, green: 0.97, blue: 0.98)  // #F5F7FA

    // Text
    static let coreText = Color(nsColor: .labelColor)
    static let coreTextSecondary = Color(nsColor: .secondaryLabelColor)
    static let coreTextTertiary = Color(nsColor: .tertiaryLabelColor)

    // Borders & dividers
    static let coreBorder = Color(nsColor: .separatorColor)
    static let coreBorderLight = Color.black.opacity(0.06)

    // Semantic
    static let coreSuccess = Color(red: 0.18, green: 0.78, blue: 0.45)
    static let coreWarning = Color(red: 0.95, green: 0.65, blue: 0.15)
    static let coreError = Color(red: 0.92, green: 0.28, blue: 0.28)

    // Aliases for backward compat
    static let corePrimary = Color.wdBrand
    static let coreSecondary = Color.wdSecondary
    static let coreAccent = Color.wdAccent
}

// MARK: - Card Modifier

struct CardStyle: ViewModifier {
    var cornerRadius: CGFloat = 12
    var padding: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.coreSurfaceCard)
                    .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.coreBorderLight, lineWidth: 1)
            )
    }
}

struct GlassBackground: ViewModifier {
    var cornerRadius: CGFloat = 10

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.coreSurfaceLight)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.coreBorder, lineWidth: 0.5)
            )
    }
}

extension View {
    func glassBackground(cornerRadius: CGFloat = 10) -> some View {
        modifier(GlassBackground(cornerRadius: cornerRadius))
    }

    func glassCard(cornerRadius: CGFloat = 12) -> some View {
        modifier(CardStyle(cornerRadius: cornerRadius))
    }

    func cardStyle(cornerRadius: CGFloat = 12, padding: CGFloat = 0) -> some View {
        modifier(CardStyle(cornerRadius: cornerRadius, padding: padding))
    }
}

// MARK: - Reusable Components

struct StatusDot: View {
    let isActive: Bool
    var activeColor: Color = .coreSuccess
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(isActive ? activeColor : Color.coreTextSecondary.opacity(0.4))
            .frame(width: size, height: size)
    }
}

struct MetricBar: View {
    let label: String
    let value: Double
    let maxValue: Double
    let unit: String
    var color: Color = .wdBrand

    var percentage: Double {
        guard maxValue > 0 else { return 0 }
        return min(value / maxValue, 1.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.coreTextSecondary)
                Spacer()
                Text(String(format: "%.1f / %.1f %@", value, maxValue, unit))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.coreText)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.coreBorderLight)
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geometry.size.width * percentage, height: 6)
                        .animation(.easeInOut(duration: 0.5), value: percentage)
                }
            }
            .frame(height: 6)
        }
    }
}

struct PulsingDot: View {
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(Color.wdBrand)
            .frame(width: 8, height: 8)
            .scaleEffect(isPulsing ? 1.3 : 1.0)
            .opacity(isPulsing ? 0.6 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}

struct LoadingIndicator: View {
    @State private var rotation = 0.0

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(Color.wdBrand, lineWidth: 2)
            .frame(width: 16, height: 16)
            .rotationEffect(.degrees(rotation))
            .animation(.linear(duration: 0.8).repeatForever(autoreverses: false), value: rotation)
            .onAppear { rotation = 360 }
    }
}

struct SectionHeader: View {
    let title: String
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(.wdBrand)
            }
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.coreText)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }
}

// MARK: - worthdoing Brand Badge

struct WorthDoingBadge: View {
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            ZStack {
                RoundedRectangle(cornerRadius: compact ? 4 : 6)
                    .fill(
                        LinearGradient(
                            colors: [.wdBrand, .wdAccent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: compact ? 18 : 24, height: compact ? 18 : 24)
                Text("W")
                    .font(.system(size: compact ? 10 : 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }

            if !compact {
                Text("worthdoing")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.wdBrand)
            }
        }
    }
}
