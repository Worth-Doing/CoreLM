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

    init(chatStore: ChatStore, modelRegistry: ModelRegistry) {
        self.chatStore = chatStore
        self.modelRegistry = modelRegistry
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
            && modelRegistry.loadedModelId != nil
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

        // Placeholder: In Phase 3+, this will call the engine via the runtime bridge.
        // For now, create a placeholder assistant message to demonstrate the UI flow.
        generationState = .generating
        streamingContent = ""

        let assistantMessage = Message(role: .assistant, content: "")
        chatStore.appendMessage(chatId: chatId, message: assistantMessage)

        // Simulate streaming for UI development
        simulateStreaming(chatId: chatId)
    }

    func stopGeneration() {
        generationState = .cancelled
    }

    func regenerate() {
        guard let chatId = currentChatId else { return }
        guard let chat = currentChat, !chat.messages.isEmpty else { return }

        // Find the last user message
        let userMessages = chat.messages.filter { $0.role == .user }
        guard let lastUserMessage = userMessages.last else { return }

        // Clear context and re-send
        chatStore.clearMessages(chatId: chatId)
        promptText = lastUserMessage.content
        sendMessage()
    }

    func clearContext() {
        guard let chatId = currentChatId else { return }
        chatStore.clearMessages(chatId: chatId)
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

    // MARK: - Placeholder Streaming Simulation

    private func simulateStreaming(chatId: UUID) {
        let words = [
            "This ", "is ", "a ", "placeholder ", "response. ",
            "The ", "inference ", "engine ", "will ", "be ",
            "connected ", "in ", "Phase ", "3. ",
            "Token ", "streaming ", "will ", "appear ", "here."
        ]
        var index = 0

        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            guard self.generationState == .generating else {
                timer.invalidate()
                self.generationState = .idle
                self.chatStore.save()
                return
            }

            if index < words.count {
                self.streamingContent += words[index]
                self.chatStore.updateLastMessage(chatId: chatId, content: self.streamingContent)
                index += 1
            } else {
                timer.invalidate()
                self.generationState = .idle
                self.chatStore.save()
            }
        }
    }
}
