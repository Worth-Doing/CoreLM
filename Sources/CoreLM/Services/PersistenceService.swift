import Foundation
import SQLite

/// SQLite-based persistence for conversations, model metadata, and settings
@MainActor
class PersistenceService: ObservableObject {
    static let shared = PersistenceService()

    private var db: Connection?

    // Tables
    private let conversations = Table("conversations")
    private let colId = SQLite.Expression<String>("id")
    private let colTitle = SQLite.Expression<String>("title")
    private let colModel = SQLite.Expression<String>("model")
    private let colMessages = SQLite.Expression<String>("messages")
    private let colSystemPrompt = SQLite.Expression<String>("system_prompt")
    private let colParameters = SQLite.Expression<String>("parameters")
    private let colCreatedAt = SQLite.Expression<Double>("created_at")
    private let colUpdatedAt = SQLite.Expression<Double>("updated_at")

    private let templates = Table("templates")
    private let colName = SQLite.Expression<String>("name")
    private let colContent = SQLite.Expression<String>("content")

    private let settings = Table("settings")
    private let colKey = SQLite.Expression<String>("key")
    private let colValue = SQLite.Expression<String>("value")

    init() {
        setupDatabase()
    }

    private func setupDatabase() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbDir = appSupport.appendingPathComponent("CoreLM")
        try? FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
        let dbPath = dbDir.appendingPathComponent("coreLM.sqlite3").path

        do {
            db = try Connection(dbPath)
            try createTables()
        } catch {
            print("Database error: \(error)")
        }
    }

    private func createTables() throws {
        try db?.run(conversations.create(ifNotExists: true) { t in
            t.column(colId, primaryKey: true)
            t.column(colTitle)
            t.column(colModel)
            t.column(colMessages)
            t.column(colSystemPrompt)
            t.column(colParameters)
            t.column(colCreatedAt)
            t.column(colUpdatedAt)
        })

        try db?.run(templates.create(ifNotExists: true) { t in
            t.column(colId, primaryKey: true)
            t.column(colName)
            t.column(colContent) // JSON-encoded PromptTemplate
            t.column(colCreatedAt)
        })

        try db?.run(settings.create(ifNotExists: true) { t in
            t.column(colKey, primaryKey: true)
            t.column(colValue)
        })
    }

    // MARK: - Conversations

    func saveConversation(_ conversation: Conversation) {
        let encoder = JSONEncoder()
        guard let messagesData = try? encoder.encode(conversation.messages),
              let messagesJSON = String(data: messagesData, encoding: .utf8),
              let paramsData = try? encoder.encode(conversation.parameters),
              let paramsJSON = String(data: paramsData, encoding: .utf8) else { return }

        let idStr = conversation.id.uuidString

        do {
            let existing = conversations.filter(colId == idStr)
            let count = try db?.scalar(existing.count) ?? 0

            if count > 0 {
                try db?.run(existing.update(
                    colTitle <- conversation.title,
                    colModel <- conversation.modelName,
                    colMessages <- messagesJSON,
                    colSystemPrompt <- conversation.systemPrompt,
                    colParameters <- paramsJSON,
                    colUpdatedAt <- conversation.updatedAt.timeIntervalSince1970
                ))
            } else {
                try db?.run(conversations.insert(
                    colId <- idStr,
                    colTitle <- conversation.title,
                    colModel <- conversation.modelName,
                    colMessages <- messagesJSON,
                    colSystemPrompt <- conversation.systemPrompt,
                    colParameters <- paramsJSON,
                    colCreatedAt <- conversation.createdAt.timeIntervalSince1970,
                    colUpdatedAt <- conversation.updatedAt.timeIntervalSince1970
                ))
            }
        } catch {
            print("Save conversation error: \(error)")
        }
    }

    func loadConversations() -> [Conversation] {
        let decoder = JSONDecoder()
        var results: [Conversation] = []

        do {
            let query = conversations.order(colUpdatedAt.desc)
            for row in try db!.prepare(query) {
                let messagesData = row[colMessages].data(using: .utf8) ?? Data()
                let paramsData = row[colParameters].data(using: .utf8) ?? Data()

                let messages = (try? decoder.decode([ChatMessage].self, from: messagesData)) ?? []
                let params = (try? decoder.decode(ChatParameters.self, from: paramsData)) ?? ChatParameters()

                let conv = Conversation(
                    id: UUID(uuidString: row[colId]) ?? UUID(),
                    title: row[colTitle],
                    modelName: row[colModel],
                    messages: messages,
                    systemPrompt: row[colSystemPrompt],
                    createdAt: Date(timeIntervalSince1970: row[colCreatedAt]),
                    updatedAt: Date(timeIntervalSince1970: row[colUpdatedAt]),
                    parameters: params
                )
                results.append(conv)
            }
        } catch {
            print("Load conversations error: \(error)")
        }

        return results
    }

    func deleteConversation(id: UUID) {
        do {
            let target = conversations.filter(colId == id.uuidString)
            try db?.run(target.delete())
        } catch {
            print("Delete conversation error: \(error)")
        }
    }

    // MARK: - Templates

    func saveTemplate(_ template: PromptTemplate) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(template),
              let json = String(data: data, encoding: .utf8) else { return }

        do {
            let existing = templates.filter(colId == template.id.uuidString)
            let count = try db?.scalar(existing.count) ?? 0

            if count > 0 {
                try db?.run(existing.update(
                    colName <- template.name,
                    colContent <- json
                ))
            } else {
                try db?.run(templates.insert(
                    colId <- template.id.uuidString,
                    colName <- template.name,
                    colContent <- json,
                    colCreatedAt <- template.createdAt.timeIntervalSince1970
                ))
            }
        } catch {
            print("Save template error: \(error)")
        }
    }

    func loadTemplates() -> [PromptTemplate] {
        let decoder = JSONDecoder()
        var results: [PromptTemplate] = []

        do {
            for row in try db!.prepare(templates.order(colCreatedAt.desc)) {
                if let data = row[colContent].data(using: .utf8),
                   let template = try? decoder.decode(PromptTemplate.self, from: data) {
                    results.append(template)
                }
            }
        } catch {
            print("Load templates error: \(error)")
        }

        return results
    }

    func deleteTemplate(id: UUID) {
        do {
            let target = templates.filter(colId == id.uuidString)
            try db?.run(target.delete())
        } catch {
            print("Delete template error: \(error)")
        }
    }

    // MARK: - Settings

    func saveSetting(key: String, value: String) {
        do {
            let existing = settings.filter(colKey == key)
            let count = try db?.scalar(existing.count) ?? 0

            if count > 0 {
                try db?.run(existing.update(colValue <- value))
            } else {
                try db?.run(settings.insert(colKey <- key, colValue <- value))
            }
        } catch {
            print("Save setting error: \(error)")
        }
    }

    func loadSetting(key: String) -> String? {
        do {
            let query = settings.filter(colKey == key)
            for row in try db!.prepare(query) {
                return row[colValue]
            }
        } catch {
            print("Load setting error: \(error)")
        }
        return nil
    }
}
