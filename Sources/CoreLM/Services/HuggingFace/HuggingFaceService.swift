import Foundation

/// Fetches models exclusively from the "worthdoing" HuggingFace organization
/// Dynamic: any new model added to the org appears automatically on refresh
@MainActor
class HuggingFaceService: ObservableObject {
    static let shared = HuggingFaceService()

    static let organization = "worthdoing"

    @Published var models: [HFModel] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var lastRefresh: Date?

    private let baseURL = "https://huggingface.co/api"

    /// Fetch ALL models from the worthdoing organization
    func fetchModels() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil

        var components = URLComponents(string: "\(baseURL)/models")!
        components.queryItems = [
            URLQueryItem(name: "author", value: Self.organization),
            URLQueryItem(name: "sort", value: "lastModified"),
            URLQueryItem(name: "direction", value: "-1"),
            URLQueryItem(name: "limit", value: "100"),
        ]

        guard let url = components.url else {
            error = "Invalid URL"
            isLoading = false
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                error = "Server error (HTTP \(code))"
                isLoading = false
                return
            }
            models = try JSONDecoder().decode([HFModel].self, from: data)
            lastRefresh = Date()
        } catch {
            self.error = "Failed to load: \(error.localizedDescription)"
        }
        isLoading = false
    }

    /// Fetch detail (files list) for a specific model
    func fetchModelDetail(modelId: String) async -> HFModelDetail? {
        let urlString = "\(baseURL)/models/\(modelId)"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            return try JSONDecoder().decode(HFModelDetail.self, from: data)
        } catch {
            return nil
        }
    }

    /// Build download URL for a file
    func getDownloadURL(modelId: String, fileName: String) -> URL? {
        guard let encodedFileName = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        return URL(string: "https://huggingface.co/\(modelId)/resolve/main/\(encodedFileName)")
    }
}
