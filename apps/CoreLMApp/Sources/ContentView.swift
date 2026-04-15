import SwiftUI

struct ContentView: View {
    @Environment(ChatStore.self) private var chatStore
    @Environment(ModelRegistry.self) private var modelRegistry
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(CoreLMRuntime.self) private var runtime

    @State private var selectedSection: SidebarSection = .chats
    @State private var selectedChatId: UUID?
    @State private var showInspector = true
    @State private var showDebugPanel = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    @State private var chatViewModel: ChatViewModel?
    @State private var modelListViewModel: ModelListViewModel?
    @State private var diagnosticsViewModel: DiagnosticsViewModel?
    @State private var settingsViewModel: SettingsViewModel?

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                selectedSection: $selectedSection,
                selectedChatId: $selectedChatId,
                chatViewModel: chatViewModel
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: Theme.sidebarWidth, max: 300)
        } detail: {
            ZStack {
                detailContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showDebugPanel {
                    VStack {
                        Spacer()
                        BottomPanelView(isVisible: $showDebugPanel)
                            .frame(height: Theme.bottomPanelHeight)
                    }
                }
            }
            .inspector(isPresented: $showInspector) {
                inspectorContent
                    .inspectorColumnWidth(min: 240, ideal: Theme.inspectorWidth, max: 350)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    showInspector.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .help("Toggle Inspector")
                .keyboardShortcut("i", modifiers: [.command, .option])

                Button {
                    showDebugPanel.toggle()
                } label: {
                    Image(systemName: "rectangle.bottomhalf.inset.filled")
                }
                .help("Toggle Debug Panel")
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }
        .onAppear {
            chatViewModel = ChatViewModel(chatStore: chatStore, modelRegistry: modelRegistry, runtime: runtime)
            modelListViewModel = ModelListViewModel(modelRegistry: modelRegistry, runtime: runtime)
            diagnosticsViewModel = DiagnosticsViewModel(modelRegistry: modelRegistry, runtime: runtime)
            settingsViewModel = SettingsViewModel(store: settingsStore)
        }
        .onReceive(NotificationCenter.default.publisher(for: .newChat)) { _ in
            chatViewModel?.newChat()
            selectedSection = .chats
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedSection {
        case .chats:
            if let vm = chatViewModel, vm.currentChatId != nil {
                ChatScreen(viewModel: vm)
            } else {
                WelcomeScreen(
                    onNewChat: {
                        chatViewModel?.newChat()
                    },
                    onImportModel: {
                        selectedSection = .models
                    }
                )
            }
        case .models:
            if let vm = modelListViewModel {
                ModelListScreen(viewModel: vm)
            }
        case .diagnostics:
            if let vm = diagnosticsViewModel {
                DiagnosticsScreen(viewModel: vm)
            }
        case .settings:
            if let vm = settingsViewModel {
                SettingsScreen(viewModel: vm)
            }
        }
    }

    @ViewBuilder
    private var inspectorContent: some View {
        switch selectedSection {
        case .chats:
            if let vm = chatViewModel {
                ChatInspector(viewModel: vm, modelRegistry: modelRegistry)
            }
        case .models:
            if let model = modelListViewModel?.models.first(where: { modelRegistry.loadedModelId == $0.id }) {
                ModelInspector(model: model)
            } else {
                Text("Select a model")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .diagnostics:
            if let vm = diagnosticsViewModel {
                RuntimeInspector(viewModel: vm)
            }
        case .settings:
            Text("Settings")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

enum SidebarSection: String, CaseIterable, Identifiable {
    case chats = "Chats"
    case models = "Models"
    case diagnostics = "Diagnostics"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .chats: return "bubble.left.and.bubble.right"
        case .models: return "cube"
        case .diagnostics: return "gauge.with.dots.needle.33percent"
        case .settings: return "gear"
        }
    }
}
