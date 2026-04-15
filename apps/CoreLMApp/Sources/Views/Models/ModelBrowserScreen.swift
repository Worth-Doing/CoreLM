import SwiftUI

struct ModelBrowserScreen: View {
    @Environment(ModelRegistry.self) private var modelRegistry

    @State private var searchText = ""
    @State private var models: [HFModelSearchResult] = []
    @State private var isSearching = false
    @State private var selectedRepo: HFModelSearchResult?
    @State private var repoFiles: [HFFileInfo] = []
    @State private var isLoadingFiles = false
    @State private var errorMessage: String?

    @State private var downloadManager = ModelDownloadManager()
    @State private var downloadingFile: HFFileInfo?

    private let client = HuggingFaceClient()
    private let runtime = CoreLMRuntime()

    var body: some View {
        VStack(spacing: 0) {
            // Header + Search
            VStack(spacing: Theme.spacing) {
                HStack {
                    Text("Browse Models")
                        .font(Theme.titleFont)
                    Spacer()
                    Link(destination: URL(string: "https://huggingface.co/models?filter=gguf")!) {
                        Label("HuggingFace", systemImage: "globe")
                            .font(Theme.captionFont)
                    }
                }

                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.tertiaryText)

                    TextField("Search GGUF models (e.g. llama, mistral, phi...)", text: $searchText)
                        .textFieldStyle(.plain)
                        .onSubmit { search() }

                    if isSearching {
                        ProgressView()
                            .controlSize(.small)
                    }

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            loadFeatured()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Theme.tertiaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Theme.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
            }
            .padding()

            Divider()

            // Content
            if let selectedRepo {
                // File list for selected repo
                fileListView(repo: selectedRepo)
            } else {
                // Model search results
                modelListView
            }
        }
        .onAppear { loadFeatured() }
        .alert("Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            if let msg = errorMessage { Text(msg) }
        }
    }

    // MARK: - Model List

    private var modelListView: some View {
        ScrollView {
            if models.isEmpty && !isSearching {
                emptySearchState
            } else {
                LazyVStack(spacing: Theme.spacing) {
                    ForEach(models) { model in
                        ModelSearchRow(model: model) {
                            selectRepo(model)
                        }
                    }
                }
                .padding()
            }
        }
    }

    private var emptySearchState: some View {
        VStack(spacing: Theme.spacingLarge) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(Theme.tertiaryText)
            Text("Search for models on HuggingFace")
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.secondaryText)
            Text("Try: llama 3.2, mistral, tinyllama, phi")
                .font(Theme.captionFont)
                .foregroundStyle(Theme.tertiaryText)
            Spacer()
        }
    }

    // MARK: - File List

    private func fileListView(repo: HFModelSearchResult) -> some View {
        VStack(spacing: 0) {
            // Back button + repo header
            HStack {
                Button {
                    selectedRepo = nil
                    repoFiles = []
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(Theme.bodyFont)
                }
                .buttonStyle(.plain)

                Spacer()

                VStack(alignment: .trailing) {
                    Text(repo.displayName)
                        .font(Theme.headlineFont)
                    Text(repo.authorName)
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .padding()

            Divider()

            if isLoadingFiles {
                VStack {
                    Spacer()
                    ProgressView("Loading files...")
                    Spacer()
                }
            } else if repoFiles.isEmpty {
                VStack {
                    Spacer()
                    Text("No GGUF files found in this repository")
                        .foregroundStyle(Theme.secondaryText)
                    Spacer()
                }
            } else {
                ScrollView {
                    // Recommendation
                    if let recommended = recommendedFile() {
                        VStack(alignment: .leading, spacing: Theme.spacingSmall) {
                            Label("Recommended", systemImage: "star.fill")
                                .font(Theme.captionFont)
                                .foregroundStyle(.orange)
                            Text("For your Mac, we recommend \(recommended.quantization) (\(recommended.fileSizeFormatted))")
                                .font(Theme.captionFont)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                        .padding(.horizontal)
                        .padding(.top, Theme.spacing)
                    }

                    LazyVStack(spacing: Theme.spacing) {
                        ForEach(repoFiles) { file in
                            GGUFFileRow(
                                file: file,
                                repoId: repo.id,
                                isDownloading: downloadingFile?.id == file.id,
                                downloadState: downloadingFile?.id == file.id ? downloadManager.state : .idle,
                                onDownload: { downloadFile(file, from: repo) },
                                onCancel: { downloadManager.cancel(); downloadingFile = nil }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
    }

    // MARK: - Actions

    private func loadFeatured() {
        isSearching = true
        Task {
            do {
                let results = try await client.featuredModels()
                await MainActor.run {
                    models = results
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    isSearching = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func search() {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        Task {
            do {
                let results = try await client.searchModels(query: searchText)
                await MainActor.run {
                    models = results
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    isSearching = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func selectRepo(_ model: HFModelSearchResult) {
        selectedRepo = model
        isLoadingFiles = true
        Task {
            do {
                let files = try await client.listFiles(repoId: model.id)
                await MainActor.run {
                    repoFiles = files
                    isLoadingFiles = false
                }
            } catch {
                await MainActor.run {
                    isLoadingFiles = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func downloadFile(_ file: HFFileInfo, from repo: HFModelSearchResult) {
        downloadingFile = file
        let url = client.downloadURL(repoId: repo.id, filename: file.path)

        // Download to Application Support/CoreLM/models/
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelsDir = appSupport.appendingPathComponent("CoreLM/models", isDirectory: true)

        Task {
            do {
                let localURL = try await downloadManager.download(url: url, filename: file.path, to: modelsDir)

                // Auto-import into registry
                await MainActor.run {
                    do {
                        var model = try modelRegistry.importModel(at: localURL)

                        // Enrich with known metadata
                        let q = file.quantization
                        if q != "unknown" { model.quantization = q }
                        model.fileSizeBytes = UInt64(file.fileSize)
                        model.name = repo.displayName + " " + q
                        modelRegistry.updateModel(model)

                        // Validate with engine
                        let (valid, info) = CoreLMRuntime.validateModel(at: localURL)
                        if valid, let info {
                            if let arch = info.architecture { model.architecture = String(cString: arch) }
                            if let quant = info.quantization { model.quantization = String(cString: quant) }
                            model.contextLength = Int(info.context_length)
                            model.embeddingLength = Int(info.embedding_length)
                            model.numLayers = Int(info.num_layers)
                            model.numHeads = Int(info.num_heads)
                            model.numKVHeads = Int(info.num_kv_heads)
                            model.vocabSize = Int(info.vocab_size)
                            modelRegistry.updateModel(model)
                        }

                        downloadingFile = nil
                    } catch {
                        errorMessage = error.localizedDescription
                        downloadingFile = nil
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Download failed: \(error.localizedDescription)"
                    downloadingFile = nil
                }
            }
        }
    }

    private func recommendedFile() -> HFFileInfo? {
        // Recommend Q4_K_M if available, else Q4_0, else smallest likely-compatible
        let byPriority = ["Q4_K_M", "Q4_K_S", "Q4_0", "Q5_K_M", "Q5_K_S", "Q8_0"]
        for target in byPriority {
            if let f = repoFiles.first(where: { $0.quantization.uppercased() == target }) {
                return f
            }
        }
        return repoFiles.first { $0.compatibility == .full || $0.compatibility == .likely }
    }
}

// MARK: - Row Components

struct ModelSearchRow: View {
    let model: HFModelSearchResult
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Theme.spacingLarge) {
                VStack(alignment: .leading, spacing: Theme.spacingSmall) {
                    Text(model.displayName)
                        .font(Theme.headlineFont)
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)

                    HStack(spacing: Theme.spacing) {
                        Text(model.authorName)
                            .font(Theme.captionFont)
                            .foregroundStyle(Theme.secondaryText)

                        if let downloads = model.downloads, downloads > 0 {
                            Label(formatCount(downloads), systemImage: "arrow.down.circle")
                                .font(Theme.captionFont)
                                .foregroundStyle(Theme.tertiaryText)
                        }

                        if let likes = model.likes, likes > 0 {
                            Label(formatCount(likes), systemImage: "heart")
                                .font(Theme.captionFont)
                                .foregroundStyle(Theme.tertiaryText)
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(Theme.tertiaryText)
            }
            .padding(Theme.spacingLarge)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .fill(Theme.secondaryBackground)
            )
        }
        .buttonStyle(.plain)
    }

    private func formatCount(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}

struct GGUFFileRow: View {
    let file: HFFileInfo
    let repoId: String
    let isDownloading: Bool
    let downloadState: ModelDownloadManager.DownloadState
    let onDownload: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: Theme.spacingLarge) {
            // Compatibility indicator
            Circle()
                .fill(compatColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: Theme.spacingSmall) {
                HStack(spacing: Theme.spacing) {
                    Text(file.quantization)
                        .font(Theme.headlineFont)

                    Text(file.compatibility.rawValue)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(compatColor.opacity(0.15))
                        .foregroundStyle(compatColor)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                HStack(spacing: Theme.spacing) {
                    Text(file.fileSizeFormatted)
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.secondaryText)

                    Text(file.path)
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.tertiaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            // Download button or progress
            if isDownloading {
                downloadProgressView
            } else {
                Button(action: onDownload) {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(file.compatibility == .unsupported)
            }
        }
        .padding(Theme.spacingLarge)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .fill(Theme.secondaryBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .stroke(isDownloading ? Theme.accent.opacity(0.3) : Theme.separator.opacity(0.3), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var downloadProgressView: some View {
        switch downloadState {
        case .downloading(let progress, let received, let total):
            VStack(alignment: .trailing, spacing: 2) {
                ProgressView(value: progress)
                    .frame(width: 100)

                HStack(spacing: 4) {
                    Text(formatBytes(received))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Theme.secondaryText)
                    Text("/")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.tertiaryText)
                    Text(formatBytes(total))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Theme.secondaryText)
                }

                Button("Cancel", action: onCancel)
                    .font(.system(size: 10))
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.error)
            }
        case .completed:
            Label("Done", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Theme.success)
                .font(Theme.captionFont)
        case .failed(let error):
            VStack(alignment: .trailing) {
                Label("Failed", systemImage: "exclamationmark.circle")
                    .foregroundStyle(Theme.error)
                    .font(Theme.captionFont)
                Text(error)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(1)
            }
        case .idle:
            EmptyView()
        }
    }

    private var compatColor: Color {
        switch file.compatibility {
        case .full: return .green
        case .likely: return .blue
        case .experimental: return .orange
        case .unsupported: return .red
        case .unknown: return .gray
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_048_576
        if mb >= 1024 { return String(format: "%.1f GB", mb / 1024) }
        return String(format: "%.0f MB", mb)
    }
}
