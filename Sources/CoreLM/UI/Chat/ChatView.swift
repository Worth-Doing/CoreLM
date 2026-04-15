import SwiftUI

/// Clean, modern chat interface — light theme
struct ChatView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            chatHeader
            Divider()

            if let conversation = appState.selectedConversation {
                if conversation.messages.isEmpty {
                    emptyState
                } else {
                    messageList(conversation: conversation)
                }
            } else {
                emptyState
            }

            Divider()
            chatInput
        }
    }

    // MARK: - Header

    private var chatHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(appState.selectedConversation?.title ?? "New Chat")
                    .font(.headline)
                    .foregroundColor(.coreText)

                HStack(spacing: 6) {
                    StatusDot(isActive: appState.ollama.isRunning)
                    Text(appState.selectedConversation?.modelName ?? "No model selected")
                        .font(.caption)
                        .foregroundColor(.coreTextSecondary)
                }
            }

            Spacer()

            if !appState.ollama.installedModels.isEmpty {
                Picker("Model", selection: Binding(
                    get: { appState.selectedConversation?.modelName ?? "" },
                    set: { name in
                        if var conv = appState.selectedConversation {
                            conv.modelName = name
                            if let idx = appState.conversations.firstIndex(where: { $0.id == conv.id }) {
                                appState.conversations[idx] = conv
                            }
                            appState.selectedConversation = conv
                        }
                    }
                )) {
                    ForEach(appState.ollama.installedModels) { model in
                        Text(model.name).tag(model.name)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 200)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Message List

    private func messageList(conversation: Conversation) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(conversation.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding(.vertical, 12)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: appState.streamingContent) { _, _ in
                scrollToBottom(proxy: proxy, conversation: conversation)
            }
            .onChange(of: conversation.messages.count) { _, _ in
                scrollToBottom(proxy: proxy, conversation: conversation)
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, conversation: Conversation) {
        if let lastMessage = conversation.messages.last {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.wdBrand.opacity(0.08))
                    .frame(width: 80, height: 80)
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.system(size: 32))
                    .foregroundColor(.wdBrand.opacity(0.5))
            }

            Text("Start a conversation")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.coreText)

            if appState.ollama.installedModels.isEmpty {
                Text("No models installed. Go to the Models tab to get started.")
                    .font(.subheadline)
                    .foregroundColor(.coreTextSecondary)
            } else {
                Text("Type a message below to begin.")
                    .font(.subheadline)
                    .foregroundColor(.coreTextSecondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Input

    private var chatInput: some View {
        HStack(spacing: 10) {
            TextField("Message...", text: $appState.currentInput, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .lineLimit(1...8)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.coreBorder, lineWidth: 1)
                )
                .onSubmit {
                    if !NSEvent.modifierFlags.contains(.shift) {
                        Task { await appState.sendMessage() }
                    }
                }

            if appState.isGenerating {
                Button(action: { appState.stopGenerating() }) {
                    Image(systemName: "stop.circle.fill")
                        .font(.title2)
                        .foregroundColor(.coreError)
                }
                .buttonStyle(.plain)
            } else {
                Button(action: { Task { await appState.sendMessage() } }) {
                    ZStack {
                        Circle()
                            .fill(appState.currentInput.trimmingCharacters(in: .whitespaces).isEmpty
                                ? Color.coreTextSecondary.opacity(0.2)
                                : Color.wdBrand)
                            .frame(width: 32, height: 32)
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)
                .disabled(appState.currentInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar
            avatar

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(message.role == .user ? "You" : "CoreLM")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(message.role == .user ? .coreText : .wdBrand)

                if message.isStreaming && message.content.isEmpty {
                    HStack(spacing: 6) {
                        PulsingDot()
                        Text("Thinking...")
                            .font(.subheadline)
                            .foregroundColor(.coreTextSecondary)
                    }
                    .padding(.vertical, 4)
                } else {
                    MarkdownContent(text: message.content)
                }
            }

            Spacer(minLength: 40)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(message.role == .assistant ? Color.coreSurface.opacity(0.5) : Color.clear)
    }

    private var avatar: some View {
        Group {
            if message.role == .user {
                ZStack {
                    Circle()
                        .fill(Color.coreTextSecondary.opacity(0.12))
                        .frame(width: 30, height: 30)
                    Image(systemName: "person.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.coreTextSecondary)
                }
            } else {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.wdBrand, .wdAccent],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 30, height: 30)
                    Image(systemName: "brain")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                }
            }
        }
        .padding(.top, 2)
    }
}

// MARK: - Markdown Rendering

struct MarkdownContent: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(parseBlocks().enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    private enum Block {
        case text(String)
        case code(language: String, content: String)
    }

    private func parseBlocks() -> [Block] {
        var blocks: [Block] = []
        let lines = text.components(separatedBy: "\n")
        var inCodeBlock = false
        var codeLanguage = ""
        var codeContent: [String] = []
        var textLines: [String] = []

        for line in lines {
            if line.hasPrefix("```") {
                if inCodeBlock {
                    blocks.append(.code(language: codeLanguage, content: codeContent.joined(separator: "\n")))
                    codeContent = []
                    codeLanguage = ""
                    inCodeBlock = false
                } else {
                    if !textLines.isEmpty {
                        blocks.append(.text(textLines.joined(separator: "\n")))
                        textLines = []
                    }
                    codeLanguage = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    inCodeBlock = true
                }
            } else if inCodeBlock {
                codeContent.append(line)
            } else {
                textLines.append(line)
            }
        }

        if inCodeBlock { blocks.append(.code(language: codeLanguage, content: codeContent.joined(separator: "\n"))) }
        if !textLines.isEmpty { blocks.append(.text(textLines.joined(separator: "\n"))) }
        return blocks
    }

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .text(let content):
            Text(attributedText(content))
                .font(.body)
                .foregroundColor(.coreText)
                .textSelection(.enabled)

        case .code(let language, let content):
            VStack(alignment: .leading, spacing: 0) {
                if !language.isEmpty {
                    HStack {
                        Text(language)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.coreTextSecondary)
                        Spacer()
                        Button(action: { copyToClipboard(content) }) {
                            Image(systemName: "doc.on.doc")
                                .font(.caption2)
                                .foregroundColor(.coreTextSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.04))
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    Text(content)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.coreText)
                        .textSelection(.enabled)
                        .padding(12)
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.coreBorder, lineWidth: 0.5)
            )
        }
    }

    private func attributedText(_ text: String) -> AttributedString {
        let result = text
        do {
            return try AttributedString(markdown: result, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        } catch {
            return AttributedString(result)
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
