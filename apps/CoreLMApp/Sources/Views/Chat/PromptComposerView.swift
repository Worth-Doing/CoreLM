import SwiftUI

struct PromptComposerView: View {
    @Binding var text: String
    let canSend: Bool
    let isGenerating: Bool
    let onSend: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: Theme.spacing) {
            TextEditor(text: $text)
                .font(Theme.bodyFont)
                .scrollContentBackground(.hidden)
                .padding(Theme.spacing)
                .background(
                    RoundedRectangle(cornerRadius: Theme.cornerRadius)
                        .fill(Theme.secondaryBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerRadius)
                        .stroke(isFocused ? Theme.accent.opacity(0.5) : Theme.separator, lineWidth: 1)
                )
                .frame(minHeight: 40, maxHeight: 120)
                .focused($isFocused)
                .onSubmit {
                    if canSend {
                        onSend()
                    }
                }

            Button(action: onSend) {
                Image(systemName: isGenerating ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(canSend ? Theme.accent : Theme.tertiaryText)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .keyboardShortcut(.return, modifiers: .command)
        }
    }
}
