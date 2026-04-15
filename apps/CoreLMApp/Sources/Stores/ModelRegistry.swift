import Foundation
import SwiftUI

@Observable
final class ModelRegistry {
    private(set) var models: [ModelInfo] = []
    var loadedModelId: UUID?
    private let storageURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("CoreLM", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.storageURL = appDir.appendingPathComponent("models.json")
        load()
    }

    var loadedModel: ModelInfo? {
        guard let id = loadedModelId else { return nil }
        return models.first { $0.id == id }
    }

    func importModel(at url: URL) throws -> ModelInfo {
        let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64 ?? 0

        let model = ModelInfo(
            id: UUID(),
            name: url.deletingPathExtension().lastPathComponent,
            architecture: "llama",
            quantization: "Q4_0",
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
        if loadedModelId == id { loadedModelId = nil }
        save()
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
}
