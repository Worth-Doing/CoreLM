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
        // Check file extension
        let ext = url.pathExtension.lowercased()
        if ext != "gguf" && ext != "bin" {
            importError = "Unsupported file type: .\(ext)\n\nCoreLM accepts .gguf model files. Download GGUF models from HuggingFace."
            return
        }

        // Check file exists and is readable
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            importError = "Cannot read file. Check permissions."
            return
        }

        // Save a security-scoped bookmark for later access
        let bookmarkData: Data?
        do {
            bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            bookmarkData = nil
        }

        // Import into registry first (so user sees it even if validation is slow)
        let model: ModelInfo
        do {
            model = try modelRegistry.importModel(at: url)
        } catch {
            importError = error.localizedDescription
            return
        }

        // Store bookmark if available
        if let bookmarkData {
            modelRegistry.setBookmark(id: model.id, data: bookmarkData)
        }

        // Try GGUF validation to enrich metadata
        let (valid, info) = CoreLMRuntime.validateModel(at: url)
        if valid, let info {
            var enriched = model
            if let name = info.name { enriched.name = String(cString: name) }
            if let arch = info.architecture { enriched.architecture = String(cString: arch) }
            if let quant = info.quantization { enriched.quantization = String(cString: quant) }
            enriched.fileSizeBytes = info.file_size_bytes
            enriched.contextLength = Int(info.context_length)
            enriched.embeddingLength = Int(info.embedding_length)
            enriched.numLayers = Int(info.num_layers)
            enriched.numHeads = Int(info.num_heads)
            enriched.numKVHeads = Int(info.num_kv_heads)
            enriched.vocabSize = Int(info.vocab_size)
            modelRegistry.updateModel(enriched)
        } else if !valid {
            // Model imported but validation failed — show warning, don't remove
            importError = "Model imported but may not load correctly.\n\nCoreLM currently supports LLaMA-architecture models with Q4_0, Q4_K, Q5_K, Q6_K, Q8_0, F16, or F32 quantization."
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
                // Try bookmark-based URL first (for security-scoped access)
                var url: URL
                var gotAccess = false
                if let bookmarkURL = modelRegistry.resolveBookmark(id: id) {
                    url = bookmarkURL
                    gotAccess = url.startAccessingSecurityScopedResource()
                } else {
                    url = URL(fileURLWithPath: model.filePath)
                }

                defer { if gotAccess { url.stopAccessingSecurityScopedResource() } }

                try await runtime.loadModel(at: url)
                await MainActor.run {
                    modelRegistry.setLoaded(id: id)
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    importError = "Failed to load model: \(error.localizedDescription)"
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

    // Accept .gguf files (custom UTType) and .bin as fallback, plus generic data
    static let allowedTypes: [UTType] = {
        var types: [UTType] = [.data, .item]
        if let gguf = UTType(filenameExtension: "gguf") {
            types.insert(gguf, at: 0)
        }
        if let bin = UTType(filenameExtension: "bin") {
            types.insert(bin, at: 0)
        }
        return types
    }()
}
