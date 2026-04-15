import Foundation

/// Native GGUF inference engine using llama.cpp's llama-server
/// Runs ANY GGUF model without Ollama — full independence
@MainActor
class NativeEngine: ObservableObject {
    static let shared = NativeEngine()

    @Published var isAvailable = false
    @Published var isRunning = false
    @Published var isInstalling = false
    @Published var installProgress = ""
    @Published var loadedModel: String?
    @Published var port: UInt16 = 8081
    @Published var logs: [String] = []

    private var serverProcess: Process?
    private var currentModelPath: String?

    private var engineDir: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CoreLM/Engine")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var serverBinaryPath: URL {
        engineDir.appendingPathComponent("llama-server")
    }

    // MARK: - Setup

    func checkAvailability() {
        isAvailable = FileManager.default.isExecutableFile(atPath: serverBinaryPath.path)
    }

    /// Download and install llama.cpp server binary
    func installEngine() async throws {
        isInstalling = true
        installProgress = "Detecting architecture..."
        defer { isInstalling = false }

        // Detect architecture
        let arch = getArchitecture()
        appendLog("Architecture: \(arch)")

        installProgress = "Downloading llama.cpp..."

        // Get latest release URL from GitHub
        let releaseURL = "https://api.github.com/repos/ggerganov/llama.cpp/releases/latest"
        guard let url = URL(string: releaseURL) else {
            throw EngineError.downloadFailed("Invalid release URL")
        }

        let (data, _) = try await URLSession.shared.data(from: url)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assets = json["assets"] as? [[String: Any]] else {
            throw EngineError.downloadFailed("Could not parse release info")
        }

        // Find the macOS asset
        let targetAsset = findMacOSAsset(assets: assets, arch: arch)

        guard let assetURL = targetAsset?["browser_download_url"] as? String,
              let downloadURL = URL(string: assetURL) else {
            // Fallback: build from source via Homebrew
            try await installViaBrew()
            return
        }

        let assetName = targetAsset?["name"] as? String ?? "llama.cpp"
        installProgress = "Downloading \(assetName)..."
        appendLog("Downloading from: \(assetURL)")

        // Download
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("coreLM-engine-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let archivePath = tempDir.appendingPathComponent(assetName)

        let (archiveData, response) = try await URLSession.shared.data(from: downloadURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw EngineError.downloadFailed("HTTP error")
        }
        try archiveData.write(to: archivePath)

        installProgress = "Extracting..."

        // Extract
        if assetName.hasSuffix(".zip") {
            let unzipProcess = Process()
            unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzipProcess.arguments = ["-o", archivePath.path, "-d", tempDir.path]
            unzipProcess.standardOutput = Pipe()
            unzipProcess.standardError = Pipe()
            try unzipProcess.run()
            unzipProcess.waitUntilExit()
        } else if assetName.hasSuffix(".tar.gz") || assetName.hasSuffix(".tgz") {
            let tarProcess = Process()
            tarProcess.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            tarProcess.arguments = ["-xzf", archivePath.path, "-C", tempDir.path]
            tarProcess.standardOutput = Pipe()
            tarProcess.standardError = Pipe()
            try tarProcess.run()
            tarProcess.waitUntilExit()
        }

        installProgress = "Installing llama-server..."

        // Find llama-server binary in extracted files
        let serverBinary = findBinary(in: tempDir, named: "llama-server")
            ?? findBinary(in: tempDir, named: "server")
            ?? findBinary(in: tempDir, named: "llama-cli")

        if let binary = serverBinary {
            if FileManager.default.fileExists(atPath: serverBinaryPath.path) {
                try FileManager.default.removeItem(at: serverBinaryPath)
            }
            try FileManager.default.copyItem(at: binary, to: serverBinaryPath)

            // Make executable
            let chmodProcess = Process()
            chmodProcess.executableURL = URL(fileURLWithPath: "/bin/chmod")
            chmodProcess.arguments = ["+x", serverBinaryPath.path]
            try chmodProcess.run()
            chmodProcess.waitUntilExit()
        } else {
            // Fallback to brew
            try await installViaBrew()
        }

        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)

        checkAvailability()
        installProgress = isAvailable ? "Engine installed!" : "Installation failed"
        appendLog(isAvailable ? "llama-server installed successfully" : "Installation failed - binary not found")
    }

    private func installViaBrew() async throws {
        installProgress = "Installing via Homebrew..."
        appendLog("Falling back to Homebrew installation...")

        let brewPaths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        guard let brewPath = brewPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw EngineError.downloadFailed("Homebrew not found. Install from brew.sh")
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: brewPath)
        process.arguments = ["install", "llama.cpp"]
        process.standardOutput = pipe
        process.standardError = pipe

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "")
        process.environment = env

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            // Find the installed binary
            let installedPaths = [
                "/opt/homebrew/bin/llama-server",
                "/usr/local/bin/llama-server",
                "/opt/homebrew/bin/llama-cli",
                "/usr/local/bin/llama-cli"
            ]
            if let found = installedPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
                try FileManager.default.copyItem(
                    at: URL(fileURLWithPath: found),
                    to: serverBinaryPath
                )
                checkAvailability()
            }
        } else {
            throw EngineError.downloadFailed("brew install llama.cpp failed")
        }
    }

    // MARK: - Model Loading

    /// Load and serve a GGUF model
    func loadModel(path: String, contextSize: Int = 4096, gpuLayers: Int = -1) async throws {
        // Stop current model if running
        if isRunning { stopModel() }

        guard FileManager.default.fileExists(atPath: path) else {
            throw EngineError.modelNotFound(path)
        }

        guard isAvailable else {
            throw EngineError.engineNotInstalled
        }

        appendLog("Loading model: \(path)")
        currentModelPath = path

        let process = Process()
        let outputPipe = Pipe()

        process.executableURL = serverBinaryPath
        process.arguments = [
            "--model", path,
            "--port", String(port),
            "--host", "127.0.0.1",
            "--ctx-size", String(contextSize),
            "--n-gpu-layers", String(gpuLayers),  // -1 = all layers on GPU
            "--threads", String(max(ProcessInfo.processInfo.activeProcessorCount - 2, 4)),
            "--parallel", "1",
            "--cont-batching",
        ]
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        // Metal acceleration for Apple Silicon
        var env = ProcessInfo.processInfo.environment
        env["GGML_METAL"] = "1"
        process.environment = env

        try process.run()
        serverProcess = process

        // Capture logs
        Task.detached { [weak self] in
            let handle = outputPipe.fileHandleForReading
            while true {
                let data = handle.availableData
                if data.isEmpty { break }
                if let line = String(data: data, encoding: .utf8) {
                    await self?.appendLog(line.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        }

        // Wait for server to be ready
        for i in 1...30 {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            if await checkNativeHealth() {
                isRunning = true
                loadedModel = URL(fileURLWithPath: path).lastPathComponent
                appendLog("Model loaded and serving on port \(port)")
                return
            }
            appendLog("Waiting for server... (\(i)/30)")
        }

        stopModel()
        throw EngineError.loadTimeout
    }

    func stopModel() {
        serverProcess?.terminate()
        serverProcess = nil
        isRunning = false
        loadedModel = nil
        currentModelPath = nil
        appendLog("Model unloaded")
    }

    // MARK: - Inference (OpenAI-compatible, same as llama-server API)

    func chat(messages: [OllamaChatMessage], options: OllamaOptions? = nil) -> AsyncStream<OllamaChatResponse> {
        AsyncStream { continuation in
            Task {
                let urlString = "http://127.0.0.1:\(port)/v1/chat/completions"
                guard let url = URL(string: urlString) else {
                    continuation.finish()
                    return
                }

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 300

                let body: [String: Any] = [
                    "messages": messages.map { ["role": $0.role, "content": $0.content] },
                    "stream": true,
                    "temperature": options?.temperature ?? 0.7,
                    "top_p": options?.topP ?? 0.9,
                ]
                request.httpBody = try? JSONSerialization.data(withJSONObject: body)

                do {
                    let (bytes, _) = try await URLSession.shared.bytes(for: request)
                    for try await line in bytes.lines {
                        // SSE format: data: {...}
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonStr = String(line.dropFirst(6))
                        if jsonStr == "[DONE]" { break }

                        guard let data = jsonStr.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let content = delta["content"] as? String else { continue }

                        let response = OllamaChatResponse(
                            model: self.loadedModel,
                            message: OllamaChatMessage(role: "assistant", content: content),
                            done: false,
                            totalDuration: nil,
                            loadDuration: nil,
                            promptEvalCount: nil,
                            evalCount: nil,
                            evalDuration: nil
                        )
                        continuation.yield(response)
                    }
                } catch {
                    await self.appendLog("Native chat error: \(error.localizedDescription)")
                }

                // Final done message
                let doneResponse = OllamaChatResponse(
                    model: self.loadedModel,
                    message: nil,
                    done: true,
                    totalDuration: nil,
                    loadDuration: nil,
                    promptEvalCount: nil,
                    evalCount: nil,
                    evalDuration: nil
                )
                continuation.yield(doneResponse)
                continuation.finish()
            }
        }
    }

    // MARK: - Health Check

    private func checkNativeHealth() async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/health") else { return false }
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Helpers

    private func getArchitecture() -> String {
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) {
                String(cString: $0)
            }
        }
        return machine // "arm64" on Apple Silicon, "x86_64" on Intel
    }

    private func findMacOSAsset(assets: [[String: Any]], arch: String) -> [String: Any]? {
        let keywords = ["macos", "darwin", "mac", "apple"]
        let archKeyword = arch == "arm64" ? "arm64" : "x86_64"

        // Try to find architecture-specific macOS build
        for asset in assets {
            guard let name = (asset["name"] as? String)?.lowercased() else { continue }
            let matchesPlatform = keywords.contains(where: { name.contains($0) })
            let matchesArch = name.contains(archKeyword) || name.contains("universal")
            if matchesPlatform && matchesArch {
                return asset
            }
        }

        // Fallback: any macOS build
        for asset in assets {
            guard let name = (asset["name"] as? String)?.lowercased() else { continue }
            if keywords.contains(where: { name.contains($0) }) {
                return asset
            }
        }

        return nil
    }

    private func findBinary(in directory: URL, named name: String) -> URL? {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isExecutableKey]) else {
            return nil
        }
        while let url = enumerator.nextObject() as? URL {
            if url.lastPathComponent == name {
                return url
            }
        }
        return nil
    }

    func appendLog(_ message: String) {
        let timestamp = DateFormatter.logFormatter.string(from: Date())
        logs.append("[\(timestamp)] \(message)")
        if logs.count > 500 {
            logs.removeFirst(logs.count - 500)
        }
    }
}

// MARK: - Errors

enum EngineError: LocalizedError {
    case downloadFailed(String)
    case modelNotFound(String)
    case engineNotInstalled
    case loadTimeout

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let msg): return "Download failed: \(msg)"
        case .modelNotFound(let path): return "Model not found: \(path)"
        case .engineNotInstalled: return "llama.cpp engine not installed. Install it from Settings."
        case .loadTimeout: return "Model loading timed out after 30 seconds"
        }
    }
}
