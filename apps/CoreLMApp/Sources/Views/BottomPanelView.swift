import SwiftUI

struct BottomPanelView: View {
    @Binding var isVisible: Bool
    @State private var logEntries: [LogEntry] = []
    @State private var autoScroll = true

    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let level: Level
        let message: String

        enum Level: String {
            case trace, debug, info, warn, error

            var color: Color {
                switch self {
                case .trace: return Theme.tertiaryText
                case .debug: return Theme.secondaryText
                case .info: return Theme.text
                case .warn: return Theme.warning
                case .error: return Theme.error
                }
            }

            var label: String { rawValue.uppercased() }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Text("Runtime Log")
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.secondaryText)

                Spacer()

                Button {
                    logEntries.removeAll()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.tertiaryText)

                Toggle(isOn: $autoScroll) {
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: 11))
                }
                .toggleStyle(.button)
                .buttonStyle(.borderless)

                Button {
                    isVisible = false
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.tertiaryText)
            }
            .padding(.horizontal, Theme.spacingLarge)
            .padding(.vertical, Theme.spacingSmall)
            .background(Theme.tertiaryBackground)

            Divider()

            // Log content
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        if logEntries.isEmpty {
                            Text("No log entries yet. Logs will appear here during model loading and generation.")
                                .font(Theme.captionFont)
                                .foregroundStyle(Theme.tertiaryText)
                                .padding()
                        } else {
                            ForEach(logEntries) { entry in
                                logRow(entry)
                                    .id(entry.id)
                            }
                        }
                    }
                }
                .onChange(of: logEntries.count) {
                    if autoScroll, let last = logEntries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .background(Theme.background)
        }
        .background(Theme.background)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func logRow(_ entry: LogEntry) -> some View {
        HStack(alignment: .top, spacing: Theme.spacing) {
            Text(entry.timestamp, format: .dateTime.hour().minute().second().secondFraction(.fractional(3)))
                .font(Theme.smallMonoFont)
                .foregroundStyle(Theme.tertiaryText)
                .frame(width: 100, alignment: .leading)

            Text(entry.level.label)
                .font(Theme.smallMonoFont)
                .foregroundStyle(entry.level.color)
                .frame(width: 50, alignment: .leading)

            Text(entry.message)
                .font(Theme.smallMonoFont)
                .foregroundStyle(Theme.text)
                .lineLimit(2)
        }
        .padding(.horizontal, Theme.spacingLarge)
        .padding(.vertical, 2)
    }
}
