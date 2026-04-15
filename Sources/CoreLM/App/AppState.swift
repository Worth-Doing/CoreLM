import SwiftUI

/// Central application state that ties all services together
@MainActor
class AppState: ObservableObject {
    // Navigation
    @Published var selectedTab: SidebarTab = .chat
    @Published var selectedConversation: Conversation?

    // Chat
    @Published var conversations: [Conversation] = []
    @Published var currentInput = ""
    @Published var isGenerating = false
    @Published var streamingContent = ""

    // Models
    @Published var selectedModel: OllamaModel?
    @Published var pullProgress: Double = 0
    @Published var isPulling = false
    @Published var pullStatus = ""

    // Engine selection
    @Published var activeEngine: InferenceEngine = .ollama

    // HuggingFace
    @Published var selectedHFModel: HFModel?

    // Services
    let ollama = OllamaService.shared
    let huggingFace = HuggingFaceService.shared
    let downloads = DownloadService.shared
    let monitor = SystemMonitor.shared
    let persistence = PersistenceService.shared
    let apiServer = LocalAPIServer.shared
    let importer = GGUFImporter.shared
    let nativeEngine = NativeEngine.shared

    init() {
        loadSavedData()
    }

    func loadSavedData() {
        conversations = persistence.loadConversations()
        if conversations.isEmpty {
            let welcome = Conversation(title: "Welcome")
            conversations = [welcome]
            selectedConversation = welcome
        } else {
            selectedConversation = conversations.first
        }
    }

    // MARK: - Startup

    func initialize() async {
        await ollama.checkInstallation()
        if ollama.isInstalled {
            await ollama.start()
        }
        nativeEngine.checkAvailability()
        monitor.startMonitoring()
        ollama.startHealthMonitoring()
    }

    // MARK: - Conversation Management

    func createNewChat() {
        let modelName = selectedModel?.name ?? ollama.installedModels.first?.name ?? ""
        let conv = Conversation(modelName: modelName)
        conversations.insert(conv, at: 0)
        selectedConversation = conv
        currentInput = ""
        streamingContent = ""
    }

    func deleteChat(_ conversation: Conversation) {
        persistence.deleteConversation(id: conversation.id)
        conversations.removeAll { $0.id == conversation.id }
        if selectedConversation?.id == conversation.id {
            selectedConversation = conversations.first
        }
    }

    // MARK: - Chat / Inference

    func sendMessage() async {
        let input = currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, !isGenerating else { return }
        guard var conversation = selectedConversation else { return }

        let modelName = conversation.modelName.isEmpty
            ? (selectedModel?.name ?? ollama.installedModels.first?.name ?? "")
            : conversation.modelName

        guard !modelName.isEmpty else { return }

        conversation.modelName = modelName

        // Add user message
        let userMessage = ChatMessage(role: .user, content: input)
        conversation.messages.append(userMessage)
        currentInput = ""
        isGenerating = true
        streamingContent = ""

        // Add placeholder assistant message
        var assistantMessage = ChatMessage(role: .assistant, content: "", isStreaming: true)
        conversation.messages.append(assistantMessage)
        updateConversation(conversation)

        // Build message list with system prompt
        var ollamaMessages: [OllamaChatMessage] = []
        if !conversation.systemPrompt.isEmpty {
            ollamaMessages.append(OllamaChatMessage(role: "system", content: conversation.systemPrompt))
        }
        ollamaMessages += conversation.messages.dropLast().map { $0.toOllamaMessage() }

        // Choose engine and stream response
        let stream: AsyncStream<OllamaChatResponse>

        if activeEngine == .native && nativeEngine.isRunning {
            stream = nativeEngine.chat(
                messages: ollamaMessages,
                options: conversation.parameters.toOllamaOptions()
            )
        } else {
            stream = ollama.chat(
                model: modelName,
                messages: ollamaMessages,
                options: conversation.parameters.toOllamaOptions()
            )
        }

        var fullContent = ""
        for await response in stream {
            if let content = response.message?.content {
                fullContent += content
                let cleaned = Self.cleanTemplateTokens(fullContent)
                streamingContent = cleaned

                // Update the last message
                assistantMessage.content = cleaned
                conversation.messages[conversation.messages.count - 1] = assistantMessage
                updateConversation(conversation)
            }

            if response.done {
                if let tps = response.tokensPerSecond {
                    monitor.updateTokenLatency(tps)
                }
            }
        }

        // Finalize — clean raw template tokens from response
        fullContent = Self.cleanTemplateTokens(fullContent)

        assistantMessage.content = fullContent
        assistantMessage = ChatMessage(
            id: assistantMessage.id,
            role: .assistant,
            content: fullContent,
            timestamp: assistantMessage.timestamp,
            isStreaming: false
        )
        conversation.messages[conversation.messages.count - 1] = assistantMessage
        conversation.updatedAt = Date()

        // Auto-title from first message
        if conversation.title == "New Chat" && !conversation.messages.isEmpty {
            let preview = input.prefix(40)
            conversation.title = String(preview) + (input.count > 40 ? "..." : "")
        }

        updateConversation(conversation)
        persistence.saveConversation(conversation)

        isGenerating = false
        streamingContent = ""
    }

    func stopGenerating() {
        isGenerating = false
        if var conversation = selectedConversation,
           let lastIndex = conversation.messages.indices.last,
           conversation.messages[lastIndex].isStreaming {
            conversation.messages[lastIndex] = ChatMessage(
                id: conversation.messages[lastIndex].id,
                role: .assistant,
                content: conversation.messages[lastIndex].content,
                timestamp: conversation.messages[lastIndex].timestamp,
                isStreaming: false
            )
            updateConversation(conversation)
            persistence.saveConversation(conversation)
        }
    }

    // MARK: - Model Management

    func pullModel(name: String) async {
        isPulling = true
        pullProgress = 0
        pullStatus = "Starting download..."

        let stream = ollama.pullModel(name: name)
        for await response in stream {
            pullStatus = response.status
            if let progress = response.progress {
                pullProgress = progress
            }
        }

        isPulling = false
        pullStatus = "Complete"
        pullProgress = 1.0
        await ollama.refreshModels()
    }

    func selectModel(_ model: OllamaModel) {
        selectedModel = model
        if var conversation = selectedConversation {
            conversation.modelName = model.name
            updateConversation(conversation)
        }
    }

    /// Load a GGUF file directly via the native engine
    func loadGGUFDirectly(path: String) async {
        do {
            try await nativeEngine.loadModel(path: path)
            activeEngine = .native
        } catch {
            ollama.appendLog("Native load failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private func updateConversation(_ conversation: Conversation) {
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index] = conversation
        }
        selectedConversation = conversation
    }

    /// Strip raw chat template tokens that some models leak into responses
    static func cleanTemplateTokens(_ text: String) -> String {
        var result = text

        // Common template tokens to strip
        let tokensToRemove = [
            "<|im_start|>assistant",
            "<|im_start|>user",
            "<|im_start|>system",
            "<|im_start|>",
            "<|im_end|>",
            "<|endoftext|>",
            "<|end_of_text|>",
            "<|eot_id|>",
            "<|start_header_id|>assistant<|end_header_id|>",
            "<|start_header_id|>user<|end_header_id|>",
            "<|start_header_id|>system<|end_header_id|>",
            "<|start_header_id|>",
            "<|end_header_id|>",
            "<|begin_of_text|>",
            "<start_of_turn>model",
            "<start_of_turn>user",
            "<start_of_turn>",
            "<end_of_turn>",
            "<|end|>",
            "<|user|>",
            "<|assistant|>",
            "<|system|>",
            "[INST]",
            "[/INST]",
            "<<SYS>>",
            "<</SYS>>",
        ]

        for token in tokensToRemove {
            result = result.replacingOccurrences(of: token, with: "")
        }

        // Clean up excessive whitespace left behind
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Engine Selection

enum InferenceEngine: String, CaseIterable, Identifiable {
    case ollama = "Ollama"
    case native = "Native (llama.cpp)"

    var id: String { rawValue }
}

// MARK: - Sidebar Tabs

enum SidebarTab: String, CaseIterable, Identifiable {
    case chat = "Chat"
    case models = "Models"
    case huggingFace = "Browse"
    case downloads = "Downloads"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right.fill"
        case .models: return "cpu.fill"
        case .huggingFace: return "globe"
        case .downloads: return "arrow.down.circle.fill"
        case .settings: return "gearshape.fill"
        }
    }
}
