import Foundation

/// Auto-imports any GGUF file into Ollama via Modelfile creation
/// This makes ALL downloaded GGUF files immediately usable
@MainActor
class GGUFImporter: ObservableObject {
    static let shared = GGUFImporter()

    @Published var importedModels: [ImportedModel] = []
    @Published var isImporting = false
    @Published var importStatus = ""

    struct ImportedModel: Identifiable, Codable {
        let id: UUID
        let name: String
        let filePath: String
        let originalFileName: String
        let sourceModelId: String
        let quantization: String?
        let importedAt: Date
        var isRegistered: Bool
    }

    private var modelsDir: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CoreLM/Models")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var modelfilesDir: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CoreLM/Modelfiles")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var registryPath: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CoreLM/imported_models.json")
    }

    init() {
        loadRegistry()
    }

    // MARK: - Import GGUF

    /// Import a GGUF file: move to models dir, create Modelfile, register with Ollama
    func importGGUF(filePath: URL, sourceModelId: String, customName: String? = nil) async throws {
        isImporting = true
        defer { isImporting = false }

        let fileName = filePath.lastPathComponent
        let modelName = customName ?? deriveModelName(from: fileName, sourceId: sourceModelId)

        importStatus = "Moving GGUF file..."

        // Move/copy file to our models directory
        let destinationPath = modelsDir.appendingPathComponent(fileName)
        if !FileManager.default.fileExists(atPath: destinationPath.path) {
            if FileManager.default.fileExists(atPath: filePath.path) {
                try FileManager.default.moveItem(at: filePath, to: destinationPath)
            }
        }

        guard FileManager.default.fileExists(atPath: destinationPath.path) else {
            throw ImportError.fileNotFound(filePath.path)
        }

        // Parse quantization from filename
        let tempSibling = HFSibling(rfilename: fileName)
        let quantization = tempSibling.quantizationType

        importStatus = "Creating Modelfile..."

        // Create Modelfile
        let modelfileContent = buildModelfile(ggufPath: destinationPath.path, modelName: modelName)
        let modelfilePath = modelfilesDir.appendingPathComponent("\(modelName).Modelfile")
        try modelfileContent.write(to: modelfilePath, atomically: true, encoding: .utf8)

        importStatus = "Registering with Ollama..."

        // Register with Ollama
        let registered = await registerWithOllama(modelName: modelName, modelfilePath: modelfilePath)

        // Save to registry
        let imported = ImportedModel(
            id: UUID(),
            name: modelName,
            filePath: destinationPath.path,
            originalFileName: fileName,
            sourceModelId: sourceModelId,
            quantization: quantization,
            importedAt: Date(),
            isRegistered: registered
        )

        importedModels.append(imported)
        saveRegistry()

        importStatus = registered ? "Imported & registered!" : "Imported (manual registration needed)"

        // Refresh Ollama model list
        await OllamaService.shared.refreshModels()
    }

    /// Import from a download that just completed
    func importFromDownload(modelId: String, fileName: String) async {
        let downloadDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CoreLM/Downloads")
        let filePath = downloadDir.appendingPathComponent(fileName)

        guard FileManager.default.fileExists(atPath: filePath.path) else {
            importStatus = "Error: Downloaded file not found"
            return
        }

        do {
            try await importGGUF(filePath: filePath, sourceModelId: modelId)
        } catch {
            importStatus = "Import failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Scan for GGUF files

    /// Scan a directory for unregistered GGUF files
    func scanForGGUFFiles() -> [URL] {
        var results: [URL] = []

        // Check our models dir
        if let files = try? FileManager.default.contentsOfDirectory(at: modelsDir, includingPropertiesForKeys: nil) {
            results += files.filter { $0.pathExtension.lowercased() == "gguf" }
        }

        // Check common locations
        let commonPaths = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache/lm-studio/models"),
        ]

        for dir in commonPaths {
            if let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                while let url = enumerator.nextObject() as? URL {
                    if url.pathExtension.lowercased() == "gguf" {
                        results.append(url)
                    }
                    // Don't recurse too deep
                    if url.pathComponents.count > dir.pathComponents.count + 3 {
                        enumerator.skipDescendants()
                    }
                }
            }
        }

        // Filter out already imported
        let importedPaths = Set(importedModels.map { $0.filePath })
        return results.filter { !importedPaths.contains($0.path) }
    }

    // MARK: - Delete

    func deleteImportedModel(_ model: ImportedModel) async {
        // Remove from Ollama
        try? await OllamaService.shared.deleteModel(name: model.name)

        // Remove GGUF file
        try? FileManager.default.removeItem(atPath: model.filePath)

        // Remove Modelfile
        let modelfilePath = modelfilesDir.appendingPathComponent("\(model.name).Modelfile")
        try? FileManager.default.removeItem(at: modelfilePath)

        // Remove from registry
        importedModels.removeAll { $0.id == model.id }
        saveRegistry()
    }

    // MARK: - Re-register

    func reRegisterModel(_ model: ImportedModel) async {
        guard FileManager.default.fileExists(atPath: model.filePath) else {
            importStatus = "GGUF file not found at \(model.filePath)"
            return
        }

        let modelfilePath = modelfilesDir.appendingPathComponent("\(model.name).Modelfile")

        // Recreate Modelfile if needed
        if !FileManager.default.fileExists(atPath: modelfilePath.path) {
            let content = buildModelfile(ggufPath: model.filePath, modelName: model.name)
            try? content.write(to: modelfilePath, atomically: true, encoding: .utf8)
        }

        let success = await registerWithOllama(modelName: model.name, modelfilePath: modelfilePath)

        if let idx = importedModels.firstIndex(where: { $0.id == model.id }) {
            importedModels[idx] = ImportedModel(
                id: model.id,
                name: model.name,
                filePath: model.filePath,
                originalFileName: model.originalFileName,
                sourceModelId: model.sourceModelId,
                quantization: model.quantization,
                importedAt: model.importedAt,
                isRegistered: success
            )
            saveRegistry()
        }

        await OllamaService.shared.refreshModels()
    }

    // MARK: - Modelfile

    private func buildModelfile(ggufPath: String, modelName: String) -> String {
        // Detect chat template from filename hints
        let lowerName = modelName.lowercased()
        let template = detectTemplate(name: lowerName)

        return """
# Auto-generated by CoreLM
# Model: \(modelName)
FROM \(ggufPath)

PARAMETER temperature 0.7
PARAMETER top_p 0.9
PARAMETER top_k 40
PARAMETER repeat_penalty 1.1
\(template)
"""
    }

    private func detectTemplate(name: String) -> String {
        // Gemma models use a specific format
        if name.contains("gemma") {
            return """
TEMPLATE \"\"\"<start_of_turn>user
{{ if .System }}{{ .System }}

{{ end }}{{ .Prompt }}<end_of_turn>
<start_of_turn>model
{{ .Response }}<end_of_turn>
\"\"\"
PARAMETER stop "<start_of_turn>"
PARAMETER stop "<end_of_turn>"
"""
        }

        // Llama 3 / Llama 3.x
        if name.contains("llama-3") || name.contains("llama3") {
            return """
TEMPLATE \"\"\"<|begin_of_text|>{{ if .System }}<|start_header_id|>system<|end_header_id|>

{{ .System }}<|eot_id|>{{ end }}<|start_header_id|>user<|end_header_id|>

{{ .Prompt }}<|eot_id|><|start_header_id|>assistant<|end_header_id|>

{{ .Response }}<|eot_id|>\"\"\"
PARAMETER stop "<|start_header_id|>"
PARAMETER stop "<|end_header_id|>"
PARAMETER stop "<|eot_id|>"
"""
        }

        // ChatML format (Qwen, Yi, Mistral-instruct, many fine-tunes)
        if name.contains("qwen") || name.contains("yi-") || name.contains("chatml")
            || name.contains("instruct") || name.contains("chat") {
            return """
TEMPLATE \"\"\"{{ if .System }}<|im_start|>system
{{ .System }}<|im_end|>
{{ end }}<|im_start|>user
{{ .Prompt }}<|im_end|>
<|im_start|>assistant
{{ .Response }}<|im_end|>
\"\"\"
PARAMETER stop "<|im_start|>"
PARAMETER stop "<|im_end|>"
PARAMETER stop "<|endoftext|>"
"""
        }

        // Mistral / Mixtral
        if name.contains("mistral") || name.contains("mixtral") {
            return """
TEMPLATE \"\"\"[INST] {{ if .System }}{{ .System }}

{{ end }}{{ .Prompt }} [/INST]
{{ .Response }}\"\"\"
PARAMETER stop "[INST]"
PARAMETER stop "[/INST]"
"""
        }

        // Phi models
        if name.contains("phi") {
            return """
TEMPLATE \"\"\"{{ if .System }}<|system|>
{{ .System }}<|end|>
{{ end }}<|user|>
{{ .Prompt }}<|end|>
<|assistant|>
{{ .Response }}<|end|>\"\"\"
PARAMETER stop "<|end|>"
PARAMETER stop "<|user|>"
PARAMETER stop "<|assistant|>"
"""
        }

        // Default: ChatML (most compatible)
        return """
TEMPLATE \"\"\"{{ if .System }}<|im_start|>system
{{ .System }}<|im_end|>
{{ end }}<|im_start|>user
{{ .Prompt }}<|im_end|>
<|im_start|>assistant
{{ .Response }}<|im_end|>
\"\"\"
PARAMETER stop "<|im_start|>"
PARAMETER stop "<|im_end|>"
PARAMETER stop "<|endoftext|>"
"""
    }

    // MARK: - Ollama Registration

    private func registerWithOllama(modelName: String, modelfilePath: URL) async -> Bool {
        // Find ollama binary
        let ollamaPaths = [
            "/usr/local/bin/ollama",
            "/opt/homebrew/bin/ollama",
            "/Applications/Ollama.app/Contents/Resources/ollama"
        ]
        guard let ollamaPath = ollamaPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            importStatus = "Ollama binary not found"
            return false
        }

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: ollamaPath)
        process.arguments = ["create", modelName, "-f", modelfilePath.path]
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            if let errStr = String(data: errData, encoding: .utf8), !errStr.isEmpty {
                OllamaService.shared.appendLog("ollama create: \(errStr)")
            }

            return process.terminationStatus == 0
        } catch {
            OllamaService.shared.appendLog("Failed to register model: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Name Derivation

    private func deriveModelName(from fileName: String, sourceId: String) -> String {
        // "TheBloke/Mistral-7B-v0.1-GGUF" + "mistral-7b-v0.1.Q4_K_M.gguf"
        // -> "mistral-7b-v0.1-q4_k_m"
        var name = fileName
            .replacingOccurrences(of: ".gguf", with: "", options: .caseInsensitive)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")

        // Remove problematic chars for Ollama model names
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        name = name.unicodeScalars.filter { allowed.contains($0) }.map { String($0) }.joined()

        // Truncate if too long
        if name.count > 60 {
            name = String(name.prefix(60))
        }

        // Ensure not empty
        if name.isEmpty {
            name = "custom-model-\(UUID().uuidString.prefix(6))"
        }

        return name
    }

    // MARK: - Registry Persistence

    private func loadRegistry() {
        guard let data = try? Data(contentsOf: registryPath),
              let models = try? JSONDecoder().decode([ImportedModel].self, from: data) else { return }
        importedModels = models
    }

    private func saveRegistry() {
        guard let data = try? JSONEncoder().encode(importedModels) else { return }
        try? data.write(to: registryPath)
    }
}

enum ImportError: LocalizedError {
    case fileNotFound(String)
    case registrationFailed(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path): return "File not found: \(path)"
        case .registrationFailed(let msg): return "Registration failed: \(msg)"
        }
    }
}
