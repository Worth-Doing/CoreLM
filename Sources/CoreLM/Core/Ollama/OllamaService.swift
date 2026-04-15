import Foundation

/// Deep wrapper around Ollama — handles installation, process lifecycle, and all API communication
@MainActor
class OllamaService: ObservableObject {
    static let shared = OllamaService()

    @Published var isInstalled = false
    @Published var isRunning = false
    @Published var installedModels: [OllamaModel] = []
    @Published var logs: [String] = []
    @Published var error: String?

    private let baseURL = "http://127.0.0.1:11434"
    private var ollamaProcess: Process?
    private var healthCheckTimer: Timer?

    // MARK: - Installation

    func checkInstallation() async {
        let path = findOllamaBinary()
        isInstalled = path != nil
        if isInstalled {
            await checkHealth()
        }
    }

    private func findOllamaBinary() -> String? {
        let paths = [
            "/usr/local/bin/ollama",
            "/opt/homebrew/bin/ollama",
            "\(NSHomeDirectory())/.ollama/bin/ollama",
            "/Applications/Ollama.app/Contents/Resources/ollama"
        ]
        for path in paths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        // Try which
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["ollama"]
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let result = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let result = result, !result.isEmpty, FileManager.default.isExecutableFile(atPath: result) {
                return result
            }
        } catch {}
        return nil
    }

    enum InstallMethod: String, CaseIterable {
        case homebrew = "Homebrew"
        case download = "Direct Download"
    }

    @Published var installProgress: String = ""
    @Published var isInstalling = false

    func installOllama(method: InstallMethod = .homebrew) async throws {
        isInstalling = true
        installProgress = ""

        defer { isInstalling = false }

        switch method {
        case .homebrew:
            try await installViaHomebrew()
        case .download:
            try await installViaDMG()
        }

        await checkInstallation()
    }

    private func installViaHomebrew() async throws {
        appendLog("Installing Ollama via Homebrew...")
        installProgress = "Checking Homebrew..."

        // Check if brew exists
        let brewPath = findBrewBinary()
        guard let brew = brewPath else {
            appendLog("Homebrew not found. Installing Homebrew first...")
            installProgress = "Installing Homebrew..."
            try await runShellCommand("/bin/bash", args: ["-c", "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""])
            guard let _ = findBrewBinary() else {
                throw OllamaError.installationFailed("Could not install Homebrew. Please install manually from https://brew.sh")
            }
            return try await installViaHomebrew()
        }

        installProgress = "Installing Ollama..."
        appendLog("Running: brew install ollama")
        try await runShellCommand(brew, args: ["install", "ollama"])

        appendLog("Ollama installed via Homebrew.")
        installProgress = "Done!"
    }

    private func installViaDMG() async throws {
        appendLog("Downloading Ollama for macOS...")
        installProgress = "Downloading Ollama.dmg..."

        let downloadURL = URL(string: "https://ollama.com/download/Ollama-darwin.zip")!
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("CoreLM-install")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let zipPath = tempDir.appendingPathComponent("Ollama-darwin.zip")

        // Download
        let (data, response) = try await URLSession.shared.data(from: downloadURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw OllamaError.installationFailed("Download failed (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0))")
        }
        try data.write(to: zipPath)
        appendLog("Downloaded \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))")

        installProgress = "Extracting..."
        // Unzip
        try await runShellCommand("/usr/bin/unzip", args: ["-o", zipPath.path, "-d", tempDir.path])

        installProgress = "Installing to /Applications..."
        // Move Ollama.app to /Applications
        let ollamaApp = tempDir.appendingPathComponent("Ollama.app")
        let destination = URL(fileURLWithPath: "/Applications/Ollama.app")

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: ollamaApp, to: destination)

        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)

        appendLog("Ollama installed to /Applications/Ollama.app")
        installProgress = "Done! Starting Ollama..."

        // Launch Ollama.app so the CLI binary gets set up
        try await runShellCommand("/usr/bin/open", args: ["/Applications/Ollama.app"])

        // Wait for it to be ready
        for i in 1...15 {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            installProgress = "Waiting for Ollama to start (\(i)/15)..."
            await checkHealth()
            if isRunning {
                appendLog("Ollama is running!")
                break
            }
        }
    }

    private func findBrewBinary() -> String? {
        let paths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        for path in paths {
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    private func runShellCommand(_ executable: String, args: [String]) async throws {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Inherit PATH for Homebrew etc.
        var env = ProcessInfo.processInfo.environment
        let extraPaths = "/opt/homebrew/bin:/usr/local/bin"
        env["PATH"] = extraPaths + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        process.environment = env

        try process.run()

        // Stream output in background
        let handle = outputPipe.fileHandleForReading
        Task.detached { [weak self] in
            while true {
                let data = handle.availableData
                if data.isEmpty { break }
                if let line = String(data: data, encoding: .utf8) {
                    await self?.appendLog(line.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        }

        process.waitUntilExit()

        // Read stderr
        let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        if let errStr = String(data: errData, encoding: .utf8), !errStr.isEmpty {
            appendLog("stderr: \(errStr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        if process.terminationStatus != 0 {
            throw OllamaError.installationFailed("\(executable) exited with code \(process.terminationStatus)")
        }
    }

    // MARK: - Process Lifecycle

    func start() async {
        guard !isRunning else { return }

        // First check if Ollama is already running (e.g. via Ollama.app)
        await checkHealth()
        if isRunning {
            appendLog("Ollama is already running.")
            await refreshModels()
            return
        }

        guard let binaryPath = findOllamaBinary() else {
            error = "Ollama binary not found. Please install Ollama."
            return
        }

        appendLog("Starting Ollama server...")

        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = ["serve"]
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        // Set environment for Apple Silicon optimization
        var env = ProcessInfo.processInfo.environment
        env["OLLAMA_HOST"] = "127.0.0.1:11434"
        process.environment = env

        do {
            try process.run()
            ollamaProcess = process

            // Capture logs
            Task.detached { [weak self] in
                let handle = outputPipe.fileHandleForReading
                while true {
                    let data = handle.availableData
                    if data.isEmpty { break }
                    if let line = String(data: data, encoding: .utf8) {
                        await self?.appendLog(line)
                    }
                }
            }

            // Wait for server to be ready
            for _ in 0..<30 {
                try await Task.sleep(nanoseconds: 500_000_000)
                await checkHealth()
                if isRunning {
                    appendLog("Ollama server started successfully.")
                    await refreshModels()
                    return
                }
            }

            error = "Ollama server failed to start within timeout."
        } catch {
            self.error = "Failed to start Ollama: \(error.localizedDescription)"
            appendLog("Error: \(error.localizedDescription)")
        }
    }

    func stop() {
        ollamaProcess?.terminate()
        ollamaProcess = nil
        isRunning = false
        appendLog("Ollama server stopped.")
    }

    func restart() async {
        stop()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        await start()
    }

    // MARK: - Health Check

    func checkHealth() async {
        guard let url = URL(string: "\(baseURL)/api/tags") else { return }
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                isRunning = true
            } else {
                isRunning = false
            }
        } catch {
            isRunning = false
        }
    }

    func startHealthMonitoring() {
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkHealth()
            }
        }
    }

    func stopHealthMonitoring() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
    }

    // MARK: - Model Management

    func refreshModels() async {
        guard let url = URL(string: "\(baseURL)/api/tags") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let list = try JSONDecoder().decode(OllamaModelList.self, from: data)
            installedModels = list.models
        } catch {
            appendLog("Error fetching models: \(error.localizedDescription)")
        }
    }

    func pullModel(name: String) -> AsyncStream<OllamaPullResponse> {
        AsyncStream { continuation in
            Task {
                guard let url = URL(string: "\(baseURL)/api/pull") else {
                    continuation.finish()
                    return
                }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                let body = ["name": name, "stream": true] as [String: Any]
                request.httpBody = try? JSONSerialization.data(withJSONObject: body)

                do {
                    let (bytes, _) = try await URLSession.shared.bytes(for: request)
                    for try await line in bytes.lines {
                        if let data = line.data(using: .utf8),
                           let response = try? JSONDecoder().decode(OllamaPullResponse.self, from: data) {
                            continuation.yield(response)
                        }
                    }
                } catch {
                    await self.appendLog("Pull error: \(error.localizedDescription)")
                }
                continuation.finish()
                await self.refreshModels()
            }
        }
    }

    func deleteModel(name: String) async throws {
        guard let url = URL(string: "\(baseURL)/api/delete") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["name": name])

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw OllamaError.deleteFailed(name)
        }
        await refreshModels()
        appendLog("Deleted model: \(name)")
    }

    // MARK: - Chat / Inference

    func chat(model: String, messages: [OllamaChatMessage], options: OllamaOptions? = nil) -> AsyncStream<OllamaChatResponse> {
        AsyncStream { continuation in
            Task {
                guard let url = URL(string: "\(baseURL)/api/chat") else {
                    continuation.finish()
                    return
                }

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 300

                let chatRequest = OllamaChatRequest(
                    model: model,
                    messages: messages,
                    stream: true,
                    options: options
                )
                request.httpBody = try? JSONEncoder().encode(chatRequest)

                do {
                    let (bytes, _) = try await URLSession.shared.bytes(for: request)
                    for try await line in bytes.lines {
                        if let data = line.data(using: .utf8),
                           let response = try? JSONDecoder().decode(OllamaChatResponse.self, from: data) {
                            continuation.yield(response)
                        }
                    }
                } catch {
                    await self.appendLog("Chat error: \(error.localizedDescription)")
                }
                continuation.finish()
            }
        }
    }

    /// Non-streaming chat for API layer
    func chatSync(model: String, messages: [OllamaChatMessage], options: OllamaOptions? = nil) async throws -> OllamaChatResponse {
        guard let url = URL(string: "\(baseURL)/api/chat") else {
            throw OllamaError.connectionFailed
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300

        let chatRequest = OllamaChatRequest(
            model: model,
            messages: messages,
            stream: false,
            options: options
        )
        request.httpBody = try JSONEncoder().encode(chatRequest)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw OllamaError.connectionFailed
        }
        return try JSONDecoder().decode(OllamaChatResponse.self, from: data)
    }

    // MARK: - Logging

    func appendLog(_ message: String) {
        let timestamp = DateFormatter.logFormatter.string(from: Date())
        let entry = "[\(timestamp)] \(message)"
        logs.append(entry)
        // Keep last 1000 log entries
        if logs.count > 1000 {
            logs.removeFirst(logs.count - 1000)
        }
    }
}

// MARK: - Errors

enum OllamaError: LocalizedError {
    case installationFailed(String)
    case connectionFailed
    case deleteFailed(String)
    case modelNotFound(String)

    var errorDescription: String? {
        switch self {
        case .installationFailed(let msg): return "Installation failed: \(msg)"
        case .connectionFailed: return "Failed to connect to Ollama server"
        case .deleteFailed(let name): return "Failed to delete model: \(name)"
        case .modelNotFound(let name): return "Model not found: \(name)"
        }
    }
}

// MARK: - DateFormatter Extension

extension DateFormatter {
    static let logFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
