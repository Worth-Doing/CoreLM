import Foundation
import SwiftUI

@Observable
final class ChatStore {
    private(set) var chats: [Chat] = []
    private let storageURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("CoreLM", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.storageURL = appDir.appendingPathComponent("chats.json")
        load()
    }

    func createChat(modelId: String? = nil) -> Chat {
        var chat = Chat(modelId: modelId)
        chat.title = "Chat \(chats.count + 1)"
        chats.insert(chat, at: 0)
        save()
        return chat
    }

    func deleteChat(id: UUID) {
        chats.removeAll { $0.id == id }
        save()
    }

    func renameChat(id: UUID, title: String) {
        guard let index = chats.firstIndex(where: { $0.id == id }) else { return }
        chats[index].title = title
        chats[index].updatedAt = Date()
        save()
    }

    func appendMessage(chatId: UUID, message: Message) {
        guard let index = chats.firstIndex(where: { $0.id == chatId }) else { return }
        chats[index].messages.append(message)
        chats[index].updatedAt = Date()
        save()
    }

    func updateLastMessage(chatId: UUID, content: String) {
        guard let index = chats.firstIndex(where: { $0.id == chatId }) else { return }
        guard !chats[index].messages.isEmpty else { return }
        let lastIdx = chats[index].messages.count - 1
        chats[index].messages[lastIdx].content = content
        chats[index].updatedAt = Date()
    }

    func clearMessages(chatId: UUID) {
        guard let index = chats.firstIndex(where: { $0.id == chatId }) else { return }
        chats[index].messages.removeAll()
        chats[index].updatedAt = Date()
        save()
    }

    func save() {
        do {
            let data = try JSONEncoder().encode(chats)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("[ChatStore] Save failed: \(error)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            chats = try JSONDecoder().decode([Chat].self, from: data)
        } catch {
            print("[ChatStore] Load failed: \(error)")
        }
    }
}
