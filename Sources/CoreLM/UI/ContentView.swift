import SwiftUI

/// Main window layout — clean light theme with worthdoing branding
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var showMonitor = true

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
        } detail: {
            HSplitView {
                mainContent
                    .frame(minWidth: 500)

                if showMonitor {
                    MonitorPanel()
                        .frame(minWidth: 230, maxWidth: 280)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: { showMonitor.toggle() }) {
                    Image(systemName: "sidebar.right")
                        .foregroundColor(.coreTextSecondary)
                }
                .help("Toggle Monitor Panel")
            }
        }
        .frame(minWidth: 960, minHeight: 620)
        .task {
            await appState.initialize()
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            // Brand header
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: [.wdBrand, .wdAccent],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 34, height: 34)
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("CoreLM")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.coreText)
                    HStack(spacing: 3) {
                        Text("by")
                            .foregroundColor(.coreTextSecondary)
                        Text("worthdoing")
                            .foregroundColor(.wdBrand)
                            .fontWeight(.semibold)
                    }
                    .font(.caption2)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            // Tabs
            VStack(spacing: 2) {
                ForEach(SidebarTab.allCases) { tab in
                    SidebarButton(tab: tab, isSelected: appState.selectedTab == tab) {
                        appState.selectedTab = tab
                    }
                }
            }
            .padding(8)

            Divider()

            // Chat list
            if appState.selectedTab == .chat {
                chatList
            }

            Spacer()

            // Status footer
            statusBar
        }
        .background(Color.coreSidebar)
    }

    // MARK: - Chat List

    private var chatList: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Conversations")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.coreTextSecondary)
                Spacer()
                Button(action: { appState.createNewChat() }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.body)
                        .foregroundColor(.wdBrand)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(appState.conversations) { conv in
                        ChatListItem(
                            conversation: conv,
                            isSelected: appState.selectedConversation?.id == conv.id
                        )
                        .onTapGesture { appState.selectedConversation = conv }
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                appState.deleteChat(conv)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        switch appState.selectedTab {
        case .chat:
            ChatView()
        case .models:
            ModelsView()
        case .huggingFace:
            HuggingFaceView()
        case .downloads:
            DownloadsView()
        case .settings:
            SettingsView()
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 6) {
            StatusDot(isActive: appState.ollama.isRunning, size: 6)
            Text(appState.ollama.isRunning ? "Ollama Connected" : "Ollama Offline")
                .font(.caption2)
                .foregroundColor(.coreTextSecondary)
            Spacer()
            if appState.monitor.tokenLatency > 0 {
                Text(String(format: "%.1f tok/s", appState.monitor.tokenLatency))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.wdAccent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Sidebar Button

struct SidebarButton: View {
    let tab: SidebarTab
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? .wdBrand : .coreTextSecondary)
                    .frame(width: 20)

                Text(tab.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .coreText : .coreTextSecondary)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Color.wdBrand.opacity(0.10) : (isHovered ? Color.coreSurfaceHover : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Chat List Item

struct ChatListItem: View {
    let conversation: Conversation
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.left")
                .font(.caption)
                .foregroundColor(isSelected ? .wdBrand : .coreTextSecondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.title)
                    .font(.caption)
                    .fontWeight(isSelected ? .medium : .regular)
                    .foregroundColor(.coreText)
                    .lineLimit(1)

                Text(conversation.modelName.isEmpty ? "No model" : conversation.modelName)
                    .font(.caption2)
                    .foregroundColor(.coreTextSecondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.wdBrand.opacity(0.08) : (isHovered ? Color.coreSurfaceHover : Color.clear))
        )
        .onHover { isHovered = $0 }
    }
}
