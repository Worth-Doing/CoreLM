import SwiftUI

@main
struct CoreLMApp: App {
    @State private var chatStore = ChatStore()
    @State private var modelRegistry = ModelRegistry()
    @State private var settingsStore = SettingsStore()
    @State private var runtime = CoreLMRuntime()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(chatStore)
                .environment(modelRegistry)
                .environment(settingsStore)
                .environment(runtime)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CoreLMCommands()
        }

        Settings {
            SettingsScreen()
                .environment(settingsStore)
        }
    }
}

struct CoreLMCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Chat") {
                NotificationCenter.default.post(name: .newChat, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)
        }
    }
}

extension Notification.Name {
    static let newChat = Notification.Name("com.corelm.newChat")
}
