import SwiftUI

/// Download manager view with progress tracking, pause/resume
struct DownloadsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.coreBorder)

            if appState.downloads.downloads.isEmpty {
                emptyState
            } else {
                downloadList
            }
        }
        .background(Color.coreSurface.opacity(0))
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Downloads")
                    .font(.headline)
                    .foregroundColor(.coreText)

                let active = appState.downloads.downloads.filter { $0.state == .downloading }.count
                Text("\(active) active, \(appState.downloads.downloads.count) total")
                    .font(.caption)
                    .foregroundColor(.coreTextSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("Disk Space")
                    .font(.caption2)
                    .foregroundColor(.coreTextSecondary)
                Text(ByteCountFormatter.string(
                    fromByteCount: appState.downloads.availableDiskSpace(),
                    countStyle: .file
                ))
                .font(.caption)
                .foregroundColor(.coreAccent)
            }
        }
        .padding(16)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 40))
                .foregroundColor(.coreTextSecondary.opacity(0.4))
            Text("No active downloads")
                .font(.body)
                .foregroundColor(.coreTextSecondary)
            Text("Browse Hugging Face to find models to download.")
                .font(.caption)
                .foregroundColor(.coreTextSecondary.opacity(0.6))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var downloadList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(appState.downloads.downloads) { task in
                    DownloadRow(task: task)
                }
            }
            .padding(16)
        }
    }
}

struct DownloadRow: View {
    let task: DownloadTask
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.fileName)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.coreText)
                        .lineLimit(1)

                    Text(task.modelId)
                        .font(.caption)
                        .foregroundColor(.coreTextSecondary)
                }

                Spacer()

                // State badge
                Text(task.state.rawValue.capitalized)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(stateColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(stateColor.opacity(0.15))
                    .cornerRadius(4)
            }

            if task.state == .downloading || task.state == .paused {
                // Progress bar
                VStack(spacing: 4) {
                    ProgressView(value: task.progress)
                        .tint(Color.corePrimary)

                    HStack {
                        Text(task.downloadedFormatted)
                            .font(.caption2)
                            .foregroundColor(.coreTextSecondary)
                        Spacer()
                        Text(task.progressFormatted)
                            .font(.caption2)
                            .foregroundColor(.coreAccent)
                        Spacer()
                        Text(task.totalFormatted)
                            .font(.caption2)
                            .foregroundColor(.coreTextSecondary)
                    }
                }
            }

            if let error = task.error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.coreError)
            }

            // Controls
            HStack(spacing: 8) {
                Spacer()

                if task.state == .downloading {
                    Button("Pause") {
                        appState.downloads.pauseDownload(id: task.id)
                    }
                    .font(.caption)
                    .foregroundColor(.coreWarning)
                    .buttonStyle(.plain)
                }

                if task.state == .paused {
                    Button("Resume") {
                        appState.downloads.resumeDownload(id: task.id)
                    }
                    .font(.caption)
                    .foregroundColor(.coreSuccess)
                    .buttonStyle(.plain)
                }

                if task.state == .downloading || task.state == .paused {
                    Button("Cancel") {
                        appState.downloads.cancelDownload(id: task.id)
                    }
                    .font(.caption)
                    .foregroundColor(.coreError)
                    .buttonStyle(.plain)
                }

                if task.state == .completed {
                    // Auto-import button
                    if task.fileName.lowercased().hasSuffix(".gguf") {
                        Button(action: {
                            Task {
                                await appState.importer.importFromDownload(
                                    modelId: task.modelId,
                                    fileName: task.fileName
                                )
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                Text("Import to CoreLM")
                            }
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.coreSuccess)
                            .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                    }

                    Button("Remove") {
                        appState.downloads.removeDownload(id: task.id)
                    }
                    .font(.caption)
                    .foregroundColor(.coreTextSecondary)
                    .buttonStyle(.plain)
                }

                if task.state == .failed || task.state == .cancelled {
                    Button("Remove") {
                        appState.downloads.removeDownload(id: task.id)
                    }
                    .font(.caption)
                    .foregroundColor(.coreTextSecondary)
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 10)
    }

    private var stateColor: Color {
        switch task.state {
        case .pending: return .coreTextSecondary
        case .downloading: return .corePrimary
        case .paused: return .coreWarning
        case .completed: return .coreSuccess
        case .failed: return .coreError
        case .cancelled: return .coreTextSecondary
        }
    }
}
