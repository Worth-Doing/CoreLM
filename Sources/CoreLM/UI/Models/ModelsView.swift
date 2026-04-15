import SwiftUI

/// Unified model management — Ollama models, imported GGUFs, native engine
struct ModelsView: View {
    @EnvironmentObject var appState: AppState
    @State private var pullModelName = ""
    @State private var showDeleteConfirm = false
    @State private var modelToDelete: OllamaModel?
    @State private var showFilePicker = false
    @State private var scannedFiles: [URL] = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.coreBorder)

            ScrollView {
                VStack(spacing: 16) {
                    engineSelector
                    nativeEngineSection
                    importSection
                    pullSection
                    importedModelsSection
                    installedSection
                }
                .padding(16)
            }
        }
        .background()
        .alert("Delete Model", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let model = modelToDelete {
                    Task { try? await appState.ollama.deleteModel(name: model.name) }
                }
            }
        } message: {
            Text("Are you sure you want to delete \(modelToDelete?.name ?? "this model")?")
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task {
                    try? await appState.importer.importGGUF(filePath: url, sourceModelId: "local-import")
                }
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Models")
                    .font(.headline)
                    .foregroundColor(.coreText)

                let totalCount = appState.ollama.installedModels.count + appState.importer.importedModels.count
                Text("\(totalCount) models available")
                    .font(.caption)
                    .foregroundColor(.coreTextSecondary)
            }

            Spacer()

            Button(action: { Task { await appState.ollama.refreshModels() } }) {
                Image(systemName: "arrow.clockwise")
                    .font(.body)
                    .foregroundColor(.coreTextSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    // MARK: - Engine Selector

    private var engineSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Inference Engine", icon: "bolt.fill")

            Picker("Engine", selection: $appState.activeEngine) {
                ForEach(InferenceEngine.allCases) { engine in
                    Text(engine.rawValue).tag(engine)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 8) {
                if appState.activeEngine == .ollama {
                    StatusDot(isActive: appState.ollama.isRunning)
                    Text(appState.ollama.isRunning ? "Ollama ready" : "Ollama not running")
                        .font(.caption)
                        .foregroundColor(appState.ollama.isRunning ? .coreSuccess : .coreError)
                } else {
                    StatusDot(isActive: appState.nativeEngine.isRunning)
                    if appState.nativeEngine.isRunning {
                        Text("Native engine running: \(appState.nativeEngine.loadedModel ?? "unknown")")
                            .font(.caption)
                            .foregroundColor(.coreSuccess)
                    } else if appState.nativeEngine.isAvailable {
                        Text("Engine ready — load a model below")
                            .font(.caption)
                            .foregroundColor(.coreWarning)
                    } else {
                        Text("Engine not installed — install below")
                            .font(.caption)
                            .foregroundColor(.coreError)
                    }
                }
                Spacer()
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 12)
    }

    // MARK: - Native Engine

    private var nativeEngineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Native Engine (llama.cpp)", icon: "cpu")

            if !appState.nativeEngine.isAvailable {
                VStack(alignment: .leading, spacing: 8) {
                    Text("The native engine lets you run ANY GGUF model directly without Ollama.")
                        .font(.caption)
                        .foregroundColor(.coreTextSecondary)

                    Button(action: {
                        Task { try? await appState.nativeEngine.installEngine() }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Install llama.cpp Engine")
                        }
                        .font(.body)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .background(Color.corePrimary)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(appState.nativeEngine.isInstalling)

                    if appState.nativeEngine.isInstalling {
                        HStack(spacing: 6) {
                            LoadingIndicator()
                            Text(appState.nativeEngine.installProgress)
                                .font(.caption)
                                .foregroundColor(.coreAccent)
                        }
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.coreSuccess)
                    Text("Engine installed")
                        .font(.caption)
                        .foregroundColor(.coreSuccess)

                    Spacer()

                    if appState.nativeEngine.isRunning {
                        Button("Stop Model") {
                            appState.nativeEngine.stopModel()
                        }
                        .font(.caption)
                        .foregroundColor(.coreError)
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 12)
    }

    // MARK: - Import GGUF

    private var importSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Import GGUF Model", icon: "square.and.arrow.down")

            Text("Load any GGUF file from your Mac. It will be registered and ready to use.")
                .font(.caption)
                .foregroundColor(.coreTextSecondary)

            HStack(spacing: 10) {
                Button(action: { showFilePicker = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                        Text("Open GGUF File...")
                    }
                    .font(.body)
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.coreSecondary)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)

                Button(action: {
                    scannedFiles = appState.importer.scanForGGUFFiles()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                        Text("Scan Mac for GGUFs")
                    }
                    .font(.body)
                    .foregroundColor(.coreText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassBackground(cornerRadius: 8)
                }
                .buttonStyle(.plain)
            }

            // Scanned files
            if !scannedFiles.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Found \(scannedFiles.count) GGUF files:")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.coreAccent)

                    ForEach(scannedFiles, id: \.absoluteString) { url in
                        HStack(spacing: 8) {
                            Image(systemName: "cube.fill")
                                .font(.caption)
                                .foregroundColor(.coreSuccess)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(url.lastPathComponent)
                                    .font(.caption)
                                    .foregroundColor(.coreText)
                                    .lineLimit(1)
                                Text(url.deletingLastPathComponent().path)
                                    .font(.caption2)
                                    .foregroundColor(.coreTextSecondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Button("Import") {
                                Task {
                                    try? await appState.importer.importGGUF(
                                        filePath: url,
                                        sourceModelId: "local-scan"
                                    )
                                    scannedFiles.removeAll { $0 == url }
                                }
                            }
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.corePrimary)
                            .buttonStyle(.plain)

                            if appState.nativeEngine.isAvailable {
                                Button("Run Direct") {
                                    Task { await appState.loadGGUFDirectly(path: url.path) }
                                }
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.coreAccent)
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(6)
                        .glassBackground(cornerRadius: 6)
                    }
                }
            }

            // Import status
            if appState.importer.isImporting {
                HStack(spacing: 6) {
                    LoadingIndicator()
                    Text(appState.importer.importStatus)
                        .font(.caption)
                        .foregroundColor(.coreAccent)
                }
            } else if !appState.importer.importStatus.isEmpty {
                Text(appState.importer.importStatus)
                    .font(.caption)
                    .foregroundColor(.coreSuccess)
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 12)
    }

    // MARK: - Imported Models

    private var importedModelsSection: some View {
        Group {
            if !appState.importer.importedModels.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Imported GGUF Models", icon: "cube.fill")

                    LazyVStack(spacing: 6) {
                        ForEach(appState.importer.importedModels) { model in
                            ImportedModelRow(model: model)
                        }
                    }
                }
                .padding(12)
                .glassCard(cornerRadius: 12)
            }
        }
    }

    // MARK: - Pull Section

    private var pullSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Pull from Ollama Registry", icon: "arrow.down.circle")

            HStack(spacing: 10) {
                TextField("Model name (e.g. llama3.2, mistral, phi3)", text: $pullModelName)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .foregroundColor(.coreText)
                    .padding(8)
                    .glassBackground(cornerRadius: 8)

                Button(action: {
                    let name = pullModelName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    Task { await appState.pullModel(name: name) }
                    pullModelName = ""
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Pull")
                    }
                    .font(.body)
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.corePrimary)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(appState.isPulling)
            }

            if appState.isPulling {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        LoadingIndicator()
                        Text(appState.pullStatus)
                            .font(.caption)
                            .foregroundColor(.coreTextSecondary)
                        Spacer()
                        Text(String(format: "%.0f%%", appState.pullProgress * 100))
                            .font(.caption)
                            .foregroundColor(.coreAccent)
                    }
                    ProgressView(value: appState.pullProgress)
                        .tint(Color.corePrimary)
                }
                .padding(12)
                .glassCard(cornerRadius: 8)
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 12)
    }

    // MARK: - Installed Models (Ollama)

    private var installedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Ollama Models", icon: "cpu")

            if appState.ollama.installedModels.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.title2)
                        .foregroundColor(.coreTextSecondary.opacity(0.4))
                    Text("No Ollama models installed")
                        .font(.caption)
                        .foregroundColor(.coreTextSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(appState.ollama.installedModels) { model in
                        ModelRow(
                            model: model,
                            isSelected: appState.selectedModel?.name == model.name,
                            onSelect: { appState.selectModel(model) },
                            onDelete: {
                                modelToDelete = model
                                showDeleteConfirm = true
                            }
                        )
                    }
                }
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 12)
    }
}

// MARK: - Imported Model Row

struct ImportedModelRow: View {
    let model: GGUFImporter.ImportedModel
    @EnvironmentObject var appState: AppState
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.coreSuccess.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: "cube.fill")
                    .font(.body)
                    .foregroundColor(.coreSuccess)
            }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(model.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.coreText)

                HStack(spacing: 6) {
                    if let quant = model.quantization {
                        Text(quant)
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.coreAccent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.coreAccent.opacity(0.15))
                            .cornerRadius(4)
                    }

                    Text(model.sourceModelId)
                        .font(.caption2)
                        .foregroundColor(.coreTextSecondary)
                        .lineLimit(1)

                    if model.isRegistered {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.coreSuccess)
                    }
                }
            }

            Spacer()

            if isHovered {
                // Load with native engine
                if appState.nativeEngine.isAvailable {
                    Button(action: {
                        Task { await appState.loadGGUFDirectly(path: model.filePath) }
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "play.fill")
                            Text("Run")
                        }
                        .font(.caption)
                        .foregroundColor(.coreAccent)
                    }
                    .buttonStyle(.plain)
                }

                // Re-register with Ollama
                if !model.isRegistered {
                    Button(action: {
                        Task { await appState.importer.reRegisterModel(model) }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                            .foregroundColor(.coreWarning)
                    }
                    .buttonStyle(.plain)
                }

                // Delete
                Button(action: {
                    Task { await appState.importer.deleteImportedModel(model) }
                }) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(.coreError)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.coreSurfaceHover : Color.clear)
        )
        .onHover { isHovered = $0 }
    }
}

// MARK: - Model Row

struct ModelRow: View {
    let model: OllamaModel
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.corePrimary.opacity(0.2) : Color.coreSurfaceCard)
                    .frame(width: 36, height: 36)
                Image(systemName: "cpu.fill")
                    .font(.body)
                    .foregroundColor(isSelected ? .corePrimary : .coreTextSecondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(model.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.coreText)

                HStack(spacing: 8) {
                    if let details = model.details {
                        if let paramSize = details.parameterSize {
                            Text(paramSize)
                                .font(.caption2)
                                .foregroundColor(.coreAccent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.coreAccent.opacity(0.15))
                                .cornerRadius(4)
                        }
                        if let quant = details.quantizationLevel {
                            Text(quant)
                                .font(.caption2)
                                .foregroundColor(.coreTextSecondary)
                        }
                    }
                    Text(model.sizeFormatted)
                        .font(.caption2)
                        .foregroundColor(.coreTextSecondary)
                }
            }

            Spacer()

            if isHovered {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(.coreError)
                }
                .buttonStyle(.plain)
            }

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.corePrimary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.corePrimary.opacity(0.08) : (isHovered ? Color.coreSurfaceHover : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.corePrimary.opacity(0.3) : Color.clear, lineWidth: 0.5)
        )
        .onHover { isHovered = $0 }
        .onTapGesture { onSelect() }
    }
}
