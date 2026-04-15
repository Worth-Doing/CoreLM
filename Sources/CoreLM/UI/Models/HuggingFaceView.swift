import SwiftUI

/// Model browser — shows all models from the worthdoing HuggingFace organization
/// Dynamically updates when new models are added to the org
struct HuggingFaceView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var hf = HuggingFaceService.shared
    @State private var selectedModel: HFModel?
    @State private var modelDetail: HFModelDetail?
    @State private var isLoadingDetail = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.coreBorder)
            content
        }
        .task {
            if hf.models.isEmpty {
                await hf.fetchModels()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            // Logo
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [.corePrimary, .coreSecondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                Text("W")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("CoreLM Models")
                    .font(.headline)
                    .foregroundColor(.coreText)
                HStack(spacing: 4) {
                    Text("by")
                        .foregroundColor(.coreTextSecondary)
                    Text("worthdoing")
                        .foregroundColor(.corePrimary)
                        .fontWeight(.medium)
                }
                .font(.caption)
            }

            Spacer()

            if let lastRefresh = hf.lastRefresh {
                Text("Updated \(lastRefresh.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundColor(.coreTextSecondary)
            }

            Button(action: {
                Task { await hf.fetchModels() }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh")
                }
                .font(.caption)
                .foregroundColor(.corePrimary)
            }
            .buttonStyle(.plain)
            .disabled(hf.isLoading)
        }
        .padding(16)
    }

    // MARK: - Content

    private var content: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                modelList
                    .frame(width: min(geo.size.width * 0.38, 380))

                Divider().background(Color.coreBorder)

                detailPanel
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Model List

    private var modelList: some View {
        ScrollView {
            VStack(spacing: 0) {
                if hf.isLoading && hf.models.isEmpty {
                    VStack(spacing: 12) {
                        Spacer().frame(height: 60)
                        LoadingIndicator()
                        Text("Loading models...")
                            .font(.caption)
                            .foregroundColor(.coreTextSecondary)
                    }
                    .frame(maxWidth: .infinity)
                } else if let error = hf.error {
                    VStack(spacing: 8) {
                        Spacer().frame(height: 40)
                        Image(systemName: "wifi.exclamationmark")
                            .font(.title2)
                            .foregroundColor(.coreError)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.coreTextSecondary)
                        Button("Retry") {
                            Task { await hf.fetchModels() }
                        }
                        .font(.caption)
                        .foregroundColor(.corePrimary)
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity)
                } else if hf.models.isEmpty {
                    VStack(spacing: 8) {
                        Spacer().frame(height: 40)
                        Text("No models published yet")
                            .font(.caption)
                            .foregroundColor(.coreTextSecondary)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    // Model count
                    HStack {
                        Text("\(hf.models.count) model\(hf.models.count == 1 ? "" : "s") available")
                            .font(.caption)
                            .foregroundColor(.coreTextSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                    LazyVStack(spacing: 4) {
                        ForEach(hf.models) { model in
                            WDModelRow(model: model, isSelected: selectedModel?.id == model.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectModel(model)
                                }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
                }
            }
        }
    }

    private func selectModel(_ model: HFModel) {
        selectedModel = model
        modelDetail = nil
        isLoadingDetail = true
        Task {
            modelDetail = await hf.fetchModelDetail(modelId: model.modelId)
            isLoadingDetail = false
        }
    }

    // MARK: - Detail Panel

    private var detailPanel: some View {
        Group {
            if isLoadingDetail {
                VStack(spacing: 12) {
                    Spacer()
                    LoadingIndicator()
                    Text("Loading files...")
                        .font(.caption)
                        .foregroundColor(.coreTextSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if let detail = modelDetail {
                modelDetailView(detail)
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 40))
                        .foregroundColor(.coreTextSecondary.opacity(0.3))
                    Text("Select a model")
                        .font(.body)
                        .foregroundColor(.coreTextSecondary)
                    Text("Choose a model from the list to see available GGUF files and download them.")
                        .font(.caption)
                        .foregroundColor(.coreTextSecondary.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color.coreSidebar)
    }

    // MARK: - Model Detail

    private func modelDetailView(_ detail: HFModelDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Title
                VStack(alignment: .leading, spacing: 6) {
                    Text(detail.modelId ?? "Unknown")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.coreText)
                        .textSelection(.enabled)

                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Image(systemName: "building.2")
                                .font(.caption2)
                            Text("worthdoing")
                        }
                        .font(.caption)
                        .foregroundColor(.corePrimary)

                        if let downloads = detail.downloads {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down.circle")
                                Text("\(downloads)")
                            }
                            .font(.caption)
                            .foregroundColor(.coreTextSecondary)
                        }

                        if let likes = detail.likes {
                            HStack(spacing: 4) {
                                Image(systemName: "heart")
                                Text("\(likes)")
                            }
                            .font(.caption)
                            .foregroundColor(.coreTextSecondary)
                        }
                    }
                }

                // Tags
                if let tags = detail.tags, !tags.isEmpty {
                    FlowLayout(spacing: 4) {
                        ForEach(tags.filter { !$0.contains(":") }.prefix(12), id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .foregroundColor(.coreAccent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.coreAccent.opacity(0.12))
                                .cornerRadius(4)
                        }
                    }
                }

                Divider().background(Color.coreBorder)

                // GGUF Files
                if let files = detail.siblings {
                    let ggufFiles = files.filter { $0.isGGUF }

                    if !ggufFiles.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 6) {
                                Image(systemName: "cube.fill")
                                    .foregroundColor(.coreSuccess)
                                Text("Available Downloads")
                                    .font(.body)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.coreText)

                                Spacer()

                                Text("\(ggufFiles.count) file\(ggufFiles.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundColor(.coreTextSecondary)
                            }

                            Text("Choose a quantization level based on your available RAM:")
                                .font(.caption)
                                .foregroundColor(.coreTextSecondary)

                            VStack(spacing: 6) {
                                ForEach(ggufFiles) { file in
                                    GGUFFileRow(
                                        file: file,
                                        modelId: detail.modelId ?? ""
                                    )
                                }
                            }
                        }
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.title3)
                                .foregroundColor(.coreWarning)
                            Text("No GGUF files in this model yet")
                                .font(.caption)
                                .foregroundColor(.coreTextSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(20)
                        .glassCard(cornerRadius: 8)
                    }
                }

                // Pull via Ollama
                if let modelId = detail.modelId {
                    Divider().background(Color.coreBorder)
                    pullSection(modelId: modelId)
                }
            }
            .padding(16)
        }
    }

    private func pullSection(modelId: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .foregroundColor(.coreWarning)
                Text("Quick Pull via Ollama")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.coreText)
            }

            Text("If this model is in the Ollama registry, pull it directly:")
                .font(.caption)
                .foregroundColor(.coreTextSecondary)

            Button(action: {
                Task { await appState.pullModel(name: modelId) }
            }) {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("Pull \(modelId)")
                }
                .font(.body)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(10)
                .background(Color.corePrimary)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(appState.isPulling)

            if appState.isPulling {
                HStack(spacing: 6) {
                    LoadingIndicator()
                    Text(appState.pullStatus)
                        .font(.caption)
                        .foregroundColor(.coreAccent)
                }
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 10)
    }
}

// MARK: - Model Row

struct WDModelRow: View {
    let model: HFModel
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.corePrimary.opacity(0.2) : Color.coreSurfaceLight)
                    .frame(width: 40, height: 40)
                Image(systemName: "cube.fill")
                    .font(.system(size: 16))
                    .foregroundColor(isSelected ? .corePrimary : .coreSuccess)
            }

            VStack(alignment: .leading, spacing: 4) {
                // Model name (without org prefix)
                Text(model.modelId.replacingOccurrences(of: "worthdoing/", with: ""))
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundColor(.coreText)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if model.isGGUF {
                        Text("GGUF")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.coreSuccess)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.coreSuccess.opacity(0.15))
                            .cornerRadius(3)
                    }

                    if let pipeline = model.pipelineTag {
                        Text(pipeline)
                            .font(.caption2)
                            .foregroundColor(.coreTextSecondary)
                    }

                    HStack(spacing: 2) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 8))
                        Text(model.downloadsFormatted)
                    }
                    .font(.caption2)
                    .foregroundColor(.coreTextSecondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundColor(.coreTextSecondary.opacity(0.4))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.corePrimary.opacity(0.12) : (isHovered ? Color.coreSurfaceHover : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.corePrimary.opacity(0.3) : Color.clear, lineWidth: 0.5)
        )
        .onHover { isHovered = $0 }
    }
}

// MARK: - GGUF File Row

struct GGUFFileRow: View {
    let file: HFSibling
    let modelId: String
    @EnvironmentObject var appState: AppState
    @State private var isHovered = false
    @State private var downloadStarted = false

    private var qualityColor: Color {
        switch file.quantizationQuality {
        case .lossless, .excellent: return .coreSuccess
        case .veryGood, .good: return .corePrimary
        case .recommended: return .coreSecondary
        case .decent: return .coreWarning
        case .small, .tiny: return .coreError
        case .unknown: return .coreTextSecondary
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            // Quantization badge
            VStack(spacing: 2) {
                Text(file.quantizationType ?? "GGUF")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(qualityColor)

                if file.quantizationQuality != .unknown {
                    Text(file.quantizationQuality.rawValue)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(qualityColor.opacity(0.8))
                }
            }
            .frame(width: 72)
            .padding(.vertical, 6)
            .background(qualityColor.opacity(0.1))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(qualityColor.opacity(0.3), lineWidth: 0.5)
            )

            // File info
            VStack(alignment: .leading, spacing: 3) {
                Text(file.rfilename)
                    .font(.caption)
                    .foregroundColor(.coreText)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let size = file.modelSizeTier {
                        Text(size)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.coreAccent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.coreAccent.opacity(0.12))
                            .cornerRadius(3)
                    }

                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.coreSuccess)
                    Text("Compatible")
                        .font(.caption2)
                        .foregroundColor(.coreSuccess)
                }
            }

            Spacer()

            // Download button
            if downloadStarted {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                    Text("Started")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundColor(.coreSuccess)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            } else {
                Button(action: downloadFile) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 14))
                        Text("Download")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.corePrimary)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.coreSurfaceHover : Color.coreSurfaceCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.coreBorder, lineWidth: 0.5)
        )
        .onHover { isHovered = $0 }
    }

    private func downloadFile() {
        guard let url = HuggingFaceService.shared.getDownloadURL(modelId: modelId, fileName: file.rfilename) else {
            return
        }
        _ = appState.downloads.startDownload(modelId: modelId, fileName: file.rfilename, url: url)
        downloadStarted = true
        appState.selectedTab = .downloads
    }
}

// MARK: - HF File Row (non-GGUF, kept for compatibility)

struct HFFileRow: View {
    let file: HFSibling
    let modelId: String
    let isCompatible: Bool
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.fill")
                .font(.caption)
                .foregroundColor(.coreTextSecondary)
            Text(file.rfilename)
                .font(.caption)
                .foregroundColor(.coreText)
                .lineLimit(1)
            Spacer()
            Text(file.formatLabel)
                .font(.caption2)
                .foregroundColor(.coreWarning)
        }
        .padding(8)
        .glassBackground(cornerRadius: 8)
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var maxHeight: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxHeight = max(maxHeight, y + rowHeight)
        }

        return (CGSize(width: maxWidth, height: maxHeight), positions)
    }
}
