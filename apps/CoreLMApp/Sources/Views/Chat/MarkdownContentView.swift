import SwiftUI

struct MarkdownContentView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            ForEach(Array(parseBlocks().enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let content):
                    Text(LocalizedStringKey(content))
                        .font(Theme.bodyFont)
                        .textSelection(.enabled)
                        .lineSpacing(4)
                        .tint(Theme.accent)

                case .code(let language, let content):
                    CodeBlockView(language: language, code: content)
                }
            }
        }
    }

    enum Block {
        case text(String)
        case code(language: String, content: String)
    }

    private func parseBlocks() -> [Block] {
        var blocks: [Block] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0
        var currentText = ""

        while i < lines.count {
            let line = lines[i]

            if line.hasPrefix("```") {
                // Flush text
                if !currentText.isEmpty {
                    blocks.append(.text(currentText.trimmingCharacters(in: .whitespacesAndNewlines)))
                    currentText = ""
                }

                let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1

                while i < lines.count && !lines[i].hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }

                let code = codeLines.joined(separator: "\n")
                blocks.append(.code(language: language, content: code))
                i += 1
            } else {
                if !currentText.isEmpty { currentText += "\n" }
                currentText += line
                i += 1
            }
        }

        if !currentText.isEmpty {
            blocks.append(.text(currentText.trimmingCharacters(in: .whitespacesAndNewlines)))
        }

        return blocks
    }
}

struct CodeBlockView: View {
    let language: String
    let code: String

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(language.isEmpty ? "code" : language)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.tertiaryText)

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copied = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                        Text(copied ? "Copied" : "Copy")
                            .font(.system(size: 10))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(copied ? Theme.success : Theme.tertiaryText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))

            Divider()

            // Code content
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(Theme.monoFont)
                    .textSelection(.enabled)
                    .lineSpacing(3)
                    .padding(12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .stroke(Theme.separator.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }
}
