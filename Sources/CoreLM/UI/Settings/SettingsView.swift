import SwiftUI

/// Application settings — chat defaults, API config, prompt templates, developer mode
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedSection: SettingsSection = .general

    enum SettingsSection: String, CaseIterable, Identifiable {
        case general = "General"
        case chatDefaults = "Chat Defaults"
        case api = "API Server"
        case templates = "Templates"
        case developer = "Developer"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .chatDefaults: return "bubble.left"
            case .api: return "network"
            case .templates: return "doc.text"
            case .developer: return "terminal"
            }
        }
    }

    var body: some View {
        HSplitView {
            // Sections sidebar
            VStack(spacing: 2) {
                ForEach(SettingsSection.allCases) { section in
                    Button(action: { selectedSection = section }) {
                        HStack(spacing: 8) {
                            Image(systemName: section.icon)
                                .font(.body)
                                .foregroundColor(selectedSection == section ? .corePrimary : .coreTextSecondary)
                                .frame(width: 20)
                            Text(section.rawValue)
                                .font(.body)
                                .foregroundColor(selectedSection == section ? .coreText : .coreTextSecondary)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selectedSection == section ? Color.corePrimary.opacity(0.1) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(12)
            .frame(width: 180)
            .background(Color.coreSidebar)

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch selectedSection {
                    case .general:
                        generalSettings
                    case .chatDefaults:
                        chatDefaultSettings
                    case .api:
                        apiSettings
                    case .templates:
                        templateSettings
                    case .developer:
                        developerSettings
                    }
                }
                .padding(20)
            }
        }
        .background()
    }

    // MARK: - General

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("General Settings")
                .font(.title2)
                .foregroundColor(.coreText)

            settingRow("Ollama Status") {
                HStack {
                    StatusDot(isActive: appState.ollama.isRunning)
                    Text(appState.ollama.isRunning ? "Connected" : "Not connected")
                        .font(.body)
                        .foregroundColor(.coreText)
                }
            }

            settingRow("Models Directory") {
                Text(appState.downloads.modelsDir.path)
                    .font(.caption)
                    .foregroundColor(.coreTextSecondary)
            }

            settingRow("Installed Models") {
                Text("\(appState.ollama.installedModels.count)")
                    .font(.body)
                    .foregroundColor(.coreText)
            }

            settingRow("Disk Space Available") {
                Text(ByteCountFormatter.string(
                    fromByteCount: appState.downloads.availableDiskSpace(),
                    countStyle: .file
                ))
                .font(.body)
                .foregroundColor(.coreText)
            }
        }
    }

    // MARK: - Chat Defaults

    @State private var defaultTemp: Double = 0.7
    @State private var defaultTopP: Double = 0.9
    @State private var defaultCtx: Double = 4096
    @State private var defaultSystemPrompt: String = "You are a helpful assistant."

    private var chatDefaultSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Chat Defaults")
                .font(.title2)
                .foregroundColor(.coreText)

            settingRow("System Prompt") {
                TextEditor(text: $defaultSystemPrompt)
                    .font(.body)
                    .foregroundColor(.coreText)
                    .frame(height: 80)
                    .padding(8)
                    .glassBackground(cornerRadius: 8)
            }

            settingRow("Temperature: \(String(format: "%.2f", defaultTemp))") {
                Slider(value: $defaultTemp, in: 0...2, step: 0.05)
                    .tint(.corePrimary)
            }

            settingRow("Top P: \(String(format: "%.2f", defaultTopP))") {
                Slider(value: $defaultTopP, in: 0...1, step: 0.05)
                    .tint(.corePrimary)
            }

            settingRow("Context Length: \(Int(defaultCtx))") {
                Slider(value: $defaultCtx, in: 512...32768, step: 512)
                    .tint(.corePrimary)
            }
        }
        .onAppear { loadChatDefaults() }
    }

    private func loadChatDefaults() {
        if let temp = appState.persistence.loadSetting(key: "default_temperature"),
           let val = Double(temp) { defaultTemp = val }
        if let topP = appState.persistence.loadSetting(key: "default_top_p"),
           let val = Double(topP) { defaultTopP = val }
        if let ctx = appState.persistence.loadSetting(key: "default_context_length"),
           let val = Double(ctx) { defaultCtx = val }
        if let sys = appState.persistence.loadSetting(key: "default_system_prompt") {
            defaultSystemPrompt = sys
        }
    }

    // MARK: - API

    @State private var apiPort: String = "8080"

    private var apiSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("API Server")
                .font(.title2)
                .foregroundColor(.coreText)

            Text("OpenAI-compatible local API for external integrations.")
                .font(.caption)
                .foregroundColor(.coreTextSecondary)

            settingRow("Port") {
                TextField("Port", text: $apiPort)
                    .textFieldStyle(.plain)
                    .foregroundColor(.coreText)
                    .frame(width: 80)
                    .padding(6)
                    .glassBackground(cornerRadius: 6)
            }

            settingRow("Status") {
                HStack {
                    StatusDot(isActive: appState.apiServer.isRunning)
                    Text(appState.apiServer.isRunning ? "Running on port \(appState.apiServer.port)" : "Stopped")
                        .font(.body)
                        .foregroundColor(.coreText)

                    Spacer()

                    Button(appState.apiServer.isRunning ? "Stop" : "Start") {
                        if appState.apiServer.isRunning {
                            appState.apiServer.stop()
                        } else {
                            if let p = UInt16(apiPort) {
                                appState.apiServer.port = p
                            }
                            appState.apiServer.start()
                        }
                    }
                    .font(.body)
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.corePrimary)
                    .cornerRadius(6)
                    .buttonStyle(.plain)
                }
            }

            settingRow("Endpoints") {
                VStack(alignment: .leading, spacing: 4) {
                    endpointLabel("POST /v1/chat/completions")
                    endpointLabel("GET  /v1/models")
                    endpointLabel("GET  /health")
                }
            }
        }
    }

    private func endpointLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .foregroundColor(.coreAccent)
    }

    // MARK: - Templates

    @State private var templates: [PromptTemplate] = []
    @State private var newTemplateName = ""
    @State private var newTemplatePrompt = ""

    private var templateSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Prompt Templates")
                .font(.title2)
                .foregroundColor(.coreText)

            // Add new template
            VStack(alignment: .leading, spacing: 8) {
                TextField("Template name", text: $newTemplateName)
                    .textFieldStyle(.plain)
                    .foregroundColor(.coreText)
                    .padding(8)
                    .glassBackground(cornerRadius: 8)

                TextEditor(text: $newTemplatePrompt)
                    .font(.body)
                    .foregroundColor(.coreText)
                    .frame(height: 60)
                    .padding(8)
                    .glassBackground(cornerRadius: 8)

                Button("Save Template") {
                    let t = PromptTemplate(name: newTemplateName, systemPrompt: newTemplatePrompt)
                    appState.persistence.saveTemplate(t)
                    templates = appState.persistence.loadTemplates()
                    newTemplateName = ""
                    newTemplatePrompt = ""
                }
                .font(.body)
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.corePrimary)
                .cornerRadius(6)
                .buttonStyle(.plain)
                .disabled(newTemplateName.isEmpty)
            }
            .padding(12)
            .glassCard(cornerRadius: 10)

            // Existing templates
            ForEach(templates) { template in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(template.name)
                            .font(.body)
                            .foregroundColor(.coreText)
                        Text(template.systemPrompt.prefix(80) + "...")
                            .font(.caption)
                            .foregroundColor(.coreTextSecondary)
                            .lineLimit(2)
                    }
                    Spacer()

                    Button(action: {
                        // Apply template to current chat
                        if var conv = appState.selectedConversation {
                            conv.systemPrompt = template.systemPrompt
                            conv.parameters = template.parameters
                            if let idx = appState.conversations.firstIndex(where: { $0.id == conv.id }) {
                                appState.conversations[idx] = conv
                            }
                            appState.selectedConversation = conv
                        }
                    }) {
                        Text("Apply")
                            .font(.caption)
                            .foregroundColor(.corePrimary)
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        appState.persistence.deleteTemplate(id: template.id)
                        templates = appState.persistence.loadTemplates()
                    }) {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundColor(.coreError)
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .glassCard(cornerRadius: 8)
            }
        }
        .onAppear { templates = appState.persistence.loadTemplates() }
    }

    // MARK: - Developer

    private var developerSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Developer Mode")
                .font(.title2)
                .foregroundColor(.coreText)

            settingRow("API Base URL") {
                Text("http://localhost:\(appState.apiServer.port)/v1")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.coreAccent)
                    .textSelection(.enabled)
            }

            settingRow("Example cURL") {
                VStack(alignment: .leading) {
                    Text("""
                    curl http://localhost:\(appState.apiServer.port)/v1/chat/completions \\
                      -H "Content-Type: application/json" \\
                      -d '{
                        "model": "\(appState.selectedModel?.name ?? "llama3.2")",
                        "messages": [{"role":"user","content":"Hello!"}]
                      }'
                    """)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.coreAccent)
                    .textSelection(.enabled)
                    .padding(10)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                }
            }

            settingRow("Python Example") {
                Text("""
                from openai import OpenAI

                client = OpenAI(
                    base_url="http://localhost:\(appState.apiServer.port)/v1",
                    api_key="not-needed"
                )

                response = client.chat.completions.create(
                    model="\(appState.selectedModel?.name ?? "llama3.2")",
                    messages=[{"role": "user", "content": "Hello!"}]
                )
                """)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.coreAccent)
                .textSelection(.enabled)
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Helpers

    private func settingRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(.coreText)
            content()
        }
    }
}
