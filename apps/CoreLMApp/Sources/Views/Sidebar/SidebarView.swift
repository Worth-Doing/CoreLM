import SwiftUI

struct SidebarView: View {
    @Binding var selectedSection: SidebarSection
    @Binding var selectedChatId: UUID?
    var chatViewModel: ChatViewModel?

    @Environment(ChatStore.self) private var chatStore

    @State private var renamingChatId: UUID?
    @State private var renameText: String = ""

    var body: some View {
        List(selection: $selectedSection) {
            Section("Chats") {
                Button {
                    chatViewModel?.newChat()
                    selectedSection = .chats
                } label: {
                    Label("New Chat", systemImage: "plus.bubble")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .padding(.vertical, 2)

                ForEach(chatStore.chats) { chat in
                    chatRow(chat)
                        .tag(SidebarSection.chats)
                        .onTapGesture {
                            selectedSection = .chats
                            selectedChatId = chat.id
                            chatViewModel?.selectChat(id: chat.id)
                        }
                }
            }

            Section("Models") {
                Label("Browse Models", systemImage: SidebarSection.browse.icon)
                    .tag(SidebarSection.browse)

                Label("My Models", systemImage: SidebarSection.models.icon)
                    .tag(SidebarSection.models)
            }

            Section("Tools") {
                Label("Diagnostics", systemImage: SidebarSection.diagnostics.icon)
                    .tag(SidebarSection.diagnostics)

                Label("Settings", systemImage: SidebarSection.settings.icon)
                    .tag(SidebarSection.settings)
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private func chatRow(_ chat: Chat) -> some View {
        if renamingChatId == chat.id {
            TextField("Chat name", text: $renameText, onCommit: {
                chatViewModel?.renameChat(id: chat.id, title: renameText)
                renamingChatId = nil
            })
            .textFieldStyle(.plain)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(chat.title)
                    .font(Theme.bodyFont)
                    .lineLimit(1)

                Text(chat.lastMessagePreview)
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
            .padding(.vertical, 2)
            .contextMenu {
                Button("Rename") {
                    renameText = chat.title
                    renamingChatId = chat.id
                }
                Divider()
                Button("Delete", role: .destructive) {
                    chatViewModel?.deleteChat(id: chat.id)
                }
            }
        }
    }
}
