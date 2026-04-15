import Foundation
import SwiftUI

@Observable
final class ModelRegistry {
    private(set) var models: [ModelInfo] = []
    var loadedModelId: UUID?
    private let storageURL: URL
    private let bookmarksURL: URL

    // Security-scoped bookmarks keyed by model ID
    private var bookmarks: [String: Data] = [:]

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("CoreLM", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.storageURL = appDir.appendingPathComponent("models.json")
        self.bookmarksURL = appDir.appendingPathComponent("bookmarks.json")
        load()
        loadBookmarks()
    }

    var loadedModel: ModelInfo? {
        guard let id = loadedModelId else { return nil }
        return models.first { $0.id == id }
    }

    func importModel(at url: URL) throws -> ModelInfo {
        // Check if already imported
        if models.contains(where: { $0.filePath == url.path }) {
            throw NSError(domain: "CoreLM", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "This model is already imported."])
        }

        let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64 ?? 0

        let model = ModelInfo(
            id: UUID(),
            name: url.deletingPathExtension().lastPathComponent,
            architecture: "unknown",
            quantization: "unknown",
            parameterCount: 0,
            fileSizeBytes: fileSize,
            contextLength: 4096,
            embeddingLength: 0,
            numLayers: 0,
            numHeads: 0,
            numKVHeads: 0,
            vocabSize: 0,
            filePath: url.path,
            addedAt: Date(),
            lastLoadedAt: nil
        )

        models.append(model)
        save()
        return model
    }

    func updateModel(_ model: ModelInfo) {
        if let index = models.firstIndex(where: { $0.id == model.id }) {
            models[index] = model
            save()
        }
    }

    func removeModel(id: UUID) {
        models.removeAll { $0.id == id }
        bookmarks.removeValue(forKey: id.uuidString)
        if loadedModelId == id { loadedModelId = nil }
        save()
        saveBookmarks()
    }

    func setLoaded(id: UUID) {
        loadedModelId = id
        if let index = models.firstIndex(where: { $0.id == id }) {
            models[index].lastLoadedAt = Date()
            save()
        }
    }

    func unload() {
        loadedModelId = nil
    }

    // MARK: - Security-Scoped Bookmarks

    func setBookmark(id: UUID, data: Data) {
        bookmarks[id.uuidString] = data
        saveBookmarks()
    }

    /// Resolve a bookmark and return a security-scoped URL (caller must start/stop access)
    func resolveBookmark(id: UUID) -> URL? {
        guard let data = bookmarks[id.uuidString] else { return nil }
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: data,
                             options: .withSecurityScope,
                             relativeTo: nil,
                             bookmarkDataIsStale: &isStale)
            if isStale {
                // Try to re-create bookmark
                if let newData = try? url.bookmarkData(options: .withSecurityScope,
                                                       includingResourceValuesForKeys: nil,
                                                       relativeTo: nil) {
                    bookmarks[id.uuidString] = newData
                    saveBookmarks()
                }
            }
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Persistence

    func save() {
        do {
            let data = try JSONEncoder().encode(models)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("[ModelRegistry] Save failed: \(error)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            models = try JSONDecoder().decode([ModelInfo].self, from: data)
        } catch {
            print("[ModelRegistry] Load failed: \(error)")
        }
    }

    private func saveBookmarks() {
        do {
            let data = try JSONEncoder().encode(bookmarks)
            try data.write(to: bookmarksURL, options: .atomic)
        } catch {
            print("[ModelRegistry] Bookmark save failed: \(error)")
        }
    }

    private func loadBookmarks() {
        guard FileManager.default.fileExists(atPath: bookmarksURL.path) else { return }
        do {
            let data = try Data(contentsOf: bookmarksURL)
            bookmarks = try JSONDecoder().decode([String: Data].self, from: data)
        } catch {
            print("[ModelRegistry] Bookmark load failed: \(error)")
        }
    }
}
