import Foundation
import SwiftUI
import UniformTypeIdentifiers

@Observable
final class ModelListViewModel {
    var isImporting = false
    var importError: String?
    var isLoading = false

    private let modelRegistry: ModelRegistry
    private let runtime: CoreLMRuntime

    init(modelRegistry: ModelRegistry, runtime: CoreLMRuntime) {
        self.modelRegistry = modelRegistry
        self.runtime = runtime
    }

    var models: [ModelInfo] {
        modelRegistry.models
    }

    var loadedModelId: UUID? {
        modelRegistry.loadedModelId
    }

    func importModel(at url: URL) {
        // Validate GGUF before importing
        let (valid, info) = CoreLMRuntime.validateModel(at: url)

        if !valid {
            importError = "Invalid or unsupported model file. CoreLM requires GGUF format with LLaMA architecture."
            return
        }

        do {
            var model = try modelRegistry.importModel(at: url)

            // Populate metadata from GGUF validation
            if let info {
                if let name = info.name { model.name = String(cString: name) }
                if let arch = info.architecture { model.architecture = String(cString: arch) }
                if let quant = info.quantization { model.quantization = String(cString: quant) }
                model.fileSizeBytes = info.file_size_bytes
                model.contextLength = Int(info.context_length)
                model.embeddingLength = Int(info.embedding_length)
                model.numLayers = Int(info.num_layers)
                model.numHeads = Int(info.num_heads)
                model.numKVHeads = Int(info.num_kv_heads)
                model.vocabSize = Int(info.vocab_size)

                // Update the model in registry with enriched metadata
                modelRegistry.updateModel(model)
            }

            importError = nil
        } catch {
            importError = error.localizedDescription
        }
    }

    func removeModel(id: UUID) {
        if modelRegistry.loadedModelId == id {
            runtime.unloadModel()
        }
        modelRegistry.removeModel(id: id)
    }

    func loadModel(id: UUID) {
        guard let model = models.first(where: { $0.id == id }) else { return }
        isLoading = true

        Task {
            do {
                let url = URL(fileURLWithPath: model.filePath)
                try await runtime.loadModel(at: url)
                await MainActor.run {
                    modelRegistry.setLoaded(id: id)
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    importError = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    func unloadModel() {
        runtime.unloadModel()
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
