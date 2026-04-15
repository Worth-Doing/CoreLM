import SwiftUI
import UniformTypeIdentifiers

struct ModelListScreen: View {
    @Bindable var viewModel: ModelListViewModel

    @State private var showFileImporter = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Models")
                    .font(Theme.titleFont)

                Spacer()

                Button {
                    showFileImporter = true
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding()

            Divider()

            // Model list
            if viewModel.models.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.spacingLarge) {
                        ForEach(viewModel.models) { model in
                            ModelCardView(
                                model: model,
                                isLoaded: viewModel.isLoaded(model),
                                isLoading: viewModel.isLoading,
                                onLoad: { viewModel.loadModel(id: model.id) },
                                onUnload: { viewModel.unloadModel() },
                                onRemove: { viewModel.removeModel(id: model.id) },
                                onShowInFinder: { viewModel.showInFinder(model) }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: ModelListViewModel.allowedTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    // Security-scoped access for sandboxed file picker URLs
                    let gotAccess = url.startAccessingSecurityScopedResource()
                    defer { if gotAccess { url.stopAccessingSecurityScopedResource() } }
                    viewModel.importModel(at: url)
                }
            case .failure(let error):
                viewModel.importError = error.localizedDescription
            }
        }
        .alert("Import Error", isPresented: .init(
            get: { viewModel.importError != nil },
            set: { if !$0 { viewModel.importError = nil } }
        )) {
            Button("OK") { viewModel.importError = nil }
        } message: {
            if let error = viewModel.importError {
                Text(error)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.spacingLarge) {
            Spacer()

            Image(systemName: "cube.transparent")
                .font(.system(size: 48))
                .foregroundStyle(Theme.tertiaryText)

            Text("No Models Imported")
                .font(Theme.headlineFont)
                .foregroundStyle(Theme.secondaryText)

            Text("Import a GGUF model file to get started")
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.tertiaryText)

            Button {
                showFileImporter = true
            } label: {
                Label("Import Model", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
