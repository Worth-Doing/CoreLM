import Foundation

// MARK: - API Models

struct HFModelSearchResult: Codable, Identifiable {
    let id: String          // e.g. "TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF"
    let modelId: String?
    let author: String?
    let downloads: Int?
    let likes: Int?
    let tags: [String]?
    let lastModified: String?

    var displayName: String {
        id.components(separatedBy: "/").last ?? id
    }

    var authorName: String {
        author ?? id.components(separatedBy: "/").first ?? "unknown"
    }
}

struct HFFileInfo: Codable, Identifiable {
    let type: String        // "file" or "directory"
    let path: String        // e.g. "tinyllama-1.1b-chat-v1.0.Q4_0.gguf"
    let size: Int64?
    let lfs: HFLFSInfo?

    var id: String { path }

    var isGGUF: Bool {
        let lp = path.lowercased()
        guard lp.hasSuffix(".gguf") else { return false }
        // Filter out vision/CLIP encoder files — not loadable as LLMs
        let visionPatterns = ["mmproj", "clip", "vision", "encoder", "projector", "image-encoder"]
        for pattern in visionPatterns {
            if lp.contains(pattern) { return false }
        }
        return true
    }

    var fileSize: Int64 {
        lfs?.size ?? size ?? 0
    }

    var fileSizeFormatted: String {
        let gb = Double(fileSize) / 1_073_741_824
        if gb >= 1.0 { return String(format: "%.1f GB", gb) }
        let mb = Double(fileSize) / 1_048_576
        return String(format: "%.0f MB", mb)
    }

    var quantization: String {
        // Extract quant from filename like "model.Q4_K_M.gguf"
        let name = path.replacingOccurrences(of: ".gguf", with: "", options: .caseInsensitive)
        let parts = name.components(separatedBy: ".")
        if let last = parts.last, last.uppercased().hasPrefix("Q") || last.uppercased().hasPrefix("F") || last.uppercased().hasPrefix("IQ") {
            return last.uppercased()
        }
        // Try with dash/underscore
        let dashParts = name.components(separatedBy: "-")
        for part in dashParts.reversed() {
            let up = part.uppercased()
            if up.hasPrefix("Q") && up.contains("_") { return up }
            if up == "F16" || up == "F32" { return up }
        }
        return "unknown"
    }

    var compatibility: ModelCompatibility {
        let q = quantization.uppercased()
        // Fully supported
        if q == "Q4_0" || q == "F16" || q == "F32" { return .full }
        // Importable (validation passes but engine may not handle dequant)
        if q.hasPrefix("Q4") || q.hasPrefix("Q5") || q.hasPrefix("Q6") || q == "Q8_0" { return .likely }
        // Small/fast
        if q.hasPrefix("Q2") || q.hasPrefix("Q3") { return .experimental }
        if q.hasPrefix("IQ") { return .unsupported }
        return .unknown
    }
}

struct HFLFSInfo: Codable {
    let size: Int64
}

enum ModelCompatibility: String {
    case full = "Supported"
    case likely = "Likely Compatible"
    case experimental = "Experimental"
    case unsupported = "Unsupported"
    case unknown = "Unknown"

    var color: String {
        switch self {
        case .full: return "green"
        case .likely: return "blue"
        case .experimental: return "orange"
        case .unsupported: return "red"
        case .unknown: return "gray"
        }
    }
}

// MARK: - Client

actor HuggingFaceClient {
    private let session = URLSession.shared
    private let baseURL = "https://huggingface.co"
    private let apiURL = "https://huggingface.co/api"

    // Search for GGUF models
    func searchModels(query: String, limit: Int = 30) async throws -> [HFModelSearchResult] {
        var searchQuery = query
        if !searchQuery.lowercased().contains("gguf") {
            searchQuery += " gguf"
        }

        var components = URLComponents(string: "\(apiURL)/models")!
        components.queryItems = [
            URLQueryItem(name: "search", value: searchQuery),
            URLQueryItem(name: "filter", value: "gguf"),
            URLQueryItem(name: "sort", value: "downloads"),
            URLQueryItem(name: "direction", value: "-1"),
            URLQueryItem(name: "limit", value: "\(limit)"),
        ]

        let (data, _) = try await session.data(from: components.url!)
        return try JSONDecoder().decode([HFModelSearchResult].self, from: data)
    }

    // Get popular/recommended GGUF models
    func featuredModels() async throws -> [HFModelSearchResult] {
        var components = URLComponents(string: "\(apiURL)/models")!
        components.queryItems = [
            URLQueryItem(name: "filter", value: "gguf"),
            URLQueryItem(name: "sort", value: "downloads"),
            URLQueryItem(name: "direction", value: "-1"),
            URLQueryItem(name: "limit", value: "40"),
        ]

        let (data, _) = try await session.data(from: components.url!)
        return try JSONDecoder().decode([HFModelSearchResult].self, from: data)
    }

    // List GGUF files in a repository
    func listFiles(repoId: String) async throws -> [HFFileInfo] {
        let url = URL(string: "\(apiURL)/models/\(repoId)/tree/main")!
        let (data, _) = try await session.data(from: url)
        let allFiles = try JSONDecoder().decode([HFFileInfo].self, from: data)
        return allFiles.filter { $0.isGGUF }.sorted { ($0.fileSize) < ($1.fileSize) }
    }

    // Download URL for a file
    nonisolated func downloadURL(repoId: String, filename: String) -> URL {
        URL(string: "https://huggingface.co/\(repoId)/resolve/main/\(filename)")!
    }
}

// MARK: - Download Manager

@Observable
final class ModelDownloadManager {
    enum DownloadState: Equatable {
        case idle
        case downloading(progress: Double, bytesReceived: Int64, totalBytes: Int64)
        case completed(localURL: URL)
        case failed(error: String)
    }

    var state: DownloadState = .idle
    var currentFilename: String = ""

    private var downloadTask: URLSessionDownloadTask?
    private var observation: NSKeyValueObservation?

    func download(url: URL, filename: String, to directory: URL) async throws -> URL {
        currentFilename = filename
        state = .downloading(progress: 0, bytesReceived: 0, totalBytes: 0)

        // Ensure download directory exists
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let destination = directory.appendingPathComponent(filename)

        // Remove existing file if present
        try? FileManager.default.removeItem(at: destination)

        return try await withCheckedThrowingContinuation { continuation in
            let task = URLSession.shared.downloadTask(with: url) { [weak self] tempURL, response, error in
                guard let self else { return }

                if let error {
                    self.state = .failed(error: error.localizedDescription)
                    continuation.resume(throwing: error)
                    return
                }

                guard let tempURL else {
                    let err = NSError(domain: "CoreLM", code: 2,
                                     userInfo: [NSLocalizedDescriptionKey: "Download produced no file"])
                    self.state = .failed(error: err.localizedDescription)
                    continuation.resume(throwing: err)
                    return
                }

                do {
                    try FileManager.default.moveItem(at: tempURL, to: destination)
                    self.state = .completed(localURL: destination)
                    continuation.resume(returning: destination)
                } catch {
                    self.state = .failed(error: error.localizedDescription)
                    continuation.resume(throwing: error)
                }
            }

            // Observe progress
            observation = task.observe(\.countOfBytesReceived) { [weak self] task, _ in
                let received = task.countOfBytesReceived
                let total = task.countOfBytesExpectedToReceive
                let progress = total > 0 ? Double(received) / Double(total) : 0
                DispatchQueue.main.async {
                    self?.state = .downloading(progress: progress, bytesReceived: received, totalBytes: total)
                }
            }

            downloadTask = task
            task.resume()
        }
    }

    func cancel() {
        downloadTask?.cancel()
        downloadTask = nil
        observation = nil
        state = .idle
    }
}
