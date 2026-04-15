import Foundation
import SwiftUI

@Observable
final class ChatViewModel {
    enum GenerationState: Equatable {
        case idle
        case generating
        case cancelled
        case error(String)
    }

    var currentChatId: UUID?
    var promptText: String = ""
    var generationState: GenerationState = .idle
    var streamingContent: String = ""
    var metrics: RuntimeMetrics = .empty

    private let chatStore: ChatStore
    private let modelRegistry: ModelRegistry
    private let runtime: CoreLMRuntime

    private var generationTask: Task<Void, Never>?

    init(chatStore: ChatStore, modelRegistry: ModelRegistry, runtime: CoreLMRuntime) {
        self.chatStore = chatStore
        self.modelRegistry = modelRegistry
        self.runtime = runtime
    }

    var currentChat: Chat? {
        guard let id = currentChatId else { return nil }
        return chatStore.chats.first { $0.id == id }
    }

    var messages: [Message] {
        currentChat?.messages ?? []
    }

    var isGenerating: Bool {
        generationState == .generating
    }

    var canSend: Bool {
        !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isGenerating
            && runtime.state == .ready
    }

    func selectChat(id: UUID) {
        currentChatId = id
        generationState = .idle
        streamingContent = ""
    }

    func newChat() {
        let chat = chatStore.createChat(modelId: modelRegistry.loadedModelId?.uuidString)
        currentChatId = chat.id
        promptText = ""
        generationState = .idle
        streamingContent = ""
    }

    func sendMessage() {
        guard canSend, let chatId = currentChatId else { return }
        let content = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        promptText = ""

        let userMessage = Message(role: .user, content: content)
        chatStore.appendMessage(chatId: chatId, message: userMessage)

        generationState = .generating
        streamingContent = ""

        let assistantMessage = Message(role: .assistant, content: "")
        chatStore.appendMessage(chatId: chatId, message: assistantMessage)

        // Launch generation via the engine
        generationTask = Task { [weak self] in
            guard let self else { return }

            do {
                let stream = self.runtime.generate(prompt: content)
                for try await token in stream {
                    guard self.generationState == .generating else { break }
                    self.streamingContent += token.text
                    self.chatStore.updateLastMessage(chatId: chatId, content: self.streamingContent)
                }
            } catch {
                if self.generationState == .generating {
                    self.generationState = .error(error.localizedDescription)
                    return
                }
            }

            self.metrics = self.runtime.metrics
            if self.generationState == .generating {
                self.generationState = .idle
            }
            self.chatStore.save()
        }
    }

    func stopGeneration() {
        generationState = .cancelled
        runtime.cancelGeneration()
        generationTask?.cancel()

        // Let the state settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.generationState = .idle
            self?.chatStore.save()
        }
    }

    func regenerate() {
        guard let chatId = currentChatId else { return }
        guard let chat = currentChat, !chat.messages.isEmpty else { return }

        let userMessages = chat.messages.filter { $0.role == .user }
        guard let lastUserMessage = userMessages.last else { return }

        chatStore.clearMessages(chatId: chatId)
        runtime.resetSession()
        promptText = lastUserMessage.content
        sendMessage()
    }

    func clearContext() {
        guard let chatId = currentChatId else { return }
        chatStore.clearMessages(chatId: chatId)
        runtime.resetSession()
        streamingContent = ""
        generationState = .idle
    }

    func deleteChat(id: UUID) {
        chatStore.deleteChat(id: id)
        if currentChatId == id {
            currentChatId = chatStore.chats.first?.id
        }
    }

    func renameChat(id: UUID, title: String) {
        chatStore.renameChat(id: id, title: title)
    }
}
