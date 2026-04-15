import Foundation

struct Chat: Identifiable, Codable {
    let id: UUID
    var title: String
    var messages: [Message]
    var modelId: String?
    let createdAt: Date
    var updatedAt: Date

    init(title: String = "New Chat", modelId: String? = nil) {
        self.id = UUID()
        self.title = title
        self.messages = []
        self.modelId = modelId
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var lastMessagePreview: String {
        messages.last?.content.prefix(80).description ?? "No messages"
    }
}
