import Foundation
import SwiftUI
import UniformTypeIdentifiers

@Observable
final class ModelListViewModel {
    var isImporting = false
    var importError: String?
    var isLoading = false

    private let modelRegistry: ModelRegistry

    init(modelRegistry: ModelRegistry) {
        self.modelRegistry = modelRegistry
    }

    var models: [ModelInfo] {
        modelRegistry.models
    }

    var loadedModelId: UUID? {
        modelRegistry.loadedModelId
    }

    func importModel(at url: URL) {
        do {
            _ = try modelRegistry.importModel(at: url)
            importError = nil
        } catch {
            importError = error.localizedDescription
        }
    }

    func removeModel(id: UUID) {
        modelRegistry.removeModel(id: id)
    }

    func loadModel(id: UUID) {
        isLoading = true
        // Phase 3+: Actually load via the runtime bridge
        // For now, simulate a brief loading delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.modelRegistry.setLoaded(id: id)
            self?.isLoading = false
        }
    }

    func unloadModel() {
        modelRegistry.unload()
    }

    func isLoaded(_ model: ModelInfo) -> Bool {
        modelRegistry.loadedModelId == model.id
    }

    func showInFinder(_ model: ModelInfo) {
        let url = URL(fileURLWithPath: model.filePath)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static let ggufType = UTType(filenameExtension: "gguf") ?? .data
}
