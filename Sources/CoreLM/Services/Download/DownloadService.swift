import Foundation

/// Download manager with real-time progress and proper file handling
class DownloadService: NSObject, ObservableObject {
    static let shared = DownloadService()

    @Published var downloads: [DownloadTask] = []

    private var delegates: [UUID: DownloadDelegate] = [:]
    private var sessions: [UUID: URLSession] = [:]
    private var tasks: [UUID: URLSessionDownloadTask] = [:]
    private var savedResumeData: [UUID: Data] = [:]

    private let downloadDir: URL

    var modelsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ollama/models")
    }

    override init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CoreLM/Downloads")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.downloadDir = dir
        super.init()
    }

    @MainActor
    func startDownload(modelId: String, fileName: String, url: URL) -> UUID {
        let taskId = UUID()
        let task = DownloadTask(
            id: taskId,
            modelId: modelId,
            fileName: fileName,
            url: url,
            progress: 0,
            downloadedBytes: 0,
            totalBytes: 0,
            state: .downloading
        )
        downloads.append(task)

        // The delegate holds all info needed to handle the download
        // without needing to call back to MainActor during file operations
        let delegate = DownloadDelegate(
            taskId: taskId,
            fileName: fileName,
            destinationDir: downloadDir,
            onProgress: { [weak self] id, written, total in
                DispatchQueue.main.async {
                    guard let self, let idx = self.downloads.firstIndex(where: { $0.id == id }) else { return }
                    self.downloads[idx].downloadedBytes = written
                    self.downloads[idx].totalBytes = total
                    self.downloads[idx].progress = total > 0 ? Double(written) / Double(total) : 0
                }
            },
            onComplete: { [weak self] id, fileURL in
                DispatchQueue.main.async {
                    guard let self, let idx = self.downloads.firstIndex(where: { $0.id == id }) else { return }
                    if let fileURL {
                        self.downloads[idx].state = .completed
                        self.downloads[idx].progress = 1.0
                        // Get real file size
                        if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                           let size = attrs[.size] as? Int64 {
                            self.downloads[idx].downloadedBytes = size
                            self.downloads[idx].totalBytes = size
                        }
                    }
                    self.tasks.removeValue(forKey: id)
                }
            },
            onError: { [weak self] id, errorMsg in
                DispatchQueue.main.async {
                    guard let self, let idx = self.downloads.firstIndex(where: { $0.id == id }) else { return }
                    self.downloads[idx].state = .failed
                    self.downloads[idx].error = errorMsg
                    self.tasks.removeValue(forKey: id)
                }
            }
        )

        delegates[taskId] = delegate

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 86400
        // Use nil delegateQueue so callbacks happen on a URLSession-managed serial queue
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        sessions[taskId] = session

        let downloadTask = session.downloadTask(with: url)
        tasks[taskId] = downloadTask
        downloadTask.resume()

        return taskId
    }

    @MainActor
    func pauseDownload(id: UUID) {
        tasks[id]?.cancel(byProducingResumeData: { [weak self] data in
            DispatchQueue.main.async {
                guard let self else { return }
                if let data { self.savedResumeData[id] = data }
                if let idx = self.downloads.firstIndex(where: { $0.id == id }) {
                    self.downloads[idx].state = .paused
                }
            }
        })
    }

    @MainActor
    func resumeDownload(id: UUID) {
        guard let idx = downloads.firstIndex(where: { $0.id == id }) else { return }

        if let data = savedResumeData[id], let session = sessions[id] {
            let downloadTask = session.downloadTask(withResumeData: data)
            tasks[id] = downloadTask
            downloads[idx].state = .downloading
            savedResumeData.removeValue(forKey: id)
            downloadTask.resume()
        } else {
            // Restart
            let dl = downloads[idx]
            let delegate = DownloadDelegate(
                taskId: id,
                fileName: dl.fileName,
                destinationDir: downloadDir,
                onProgress: { [weak self] tid, written, total in
                    DispatchQueue.main.async {
                        guard let self, let i = self.downloads.firstIndex(where: { $0.id == tid }) else { return }
                        self.downloads[i].downloadedBytes = written
                        self.downloads[i].totalBytes = total
                        self.downloads[i].progress = total > 0 ? Double(written) / Double(total) : 0
                    }
                },
                onComplete: { [weak self] tid, fileURL in
                    DispatchQueue.main.async {
                        guard let self, let i = self.downloads.firstIndex(where: { $0.id == tid }) else { return }
                        if fileURL != nil {
                            self.downloads[i].state = .completed
                            self.downloads[i].progress = 1.0
                        }
                    }
                },
                onError: { [weak self] tid, errorMsg in
                    DispatchQueue.main.async {
                        guard let self, let i = self.downloads.firstIndex(where: { $0.id == tid }) else { return }
                        self.downloads[i].state = .failed
                        self.downloads[i].error = errorMsg
                    }
                }
            )
            delegates[id] = delegate

            let config = URLSessionConfiguration.default
            config.timeoutIntervalForResource = 86400
            let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            sessions[id] = session

            let downloadTask = session.downloadTask(with: dl.url)
            tasks[id] = downloadTask
            downloads[idx].state = .downloading
            downloadTask.resume()
        }
    }

    @MainActor
    func cancelDownload(id: UUID) {
        tasks[id]?.cancel()
        tasks.removeValue(forKey: id)
        sessions[id]?.invalidateAndCancel()
        sessions.removeValue(forKey: id)
        delegates.removeValue(forKey: id)
        savedResumeData.removeValue(forKey: id)
        if let idx = downloads.firstIndex(where: { $0.id == id }) {
            downloads[idx].state = .cancelled
        }
    }

    @MainActor
    func removeDownload(id: UUID) {
        cancelDownload(id: id)
        downloads.removeAll { $0.id == id }
    }

    func availableDiskSpace() -> Int64 {
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
            return attrs[.systemFreeSize] as? Int64 ?? 0
        } catch {
            return 0
        }
    }
}

// MARK: - Download Delegate
// Self-contained: holds fileName and destinationDir so it can do file I/O
// synchronously in didFinishDownloadingTo without touching the main thread

class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let taskId: UUID
    let fileName: String
    let destinationDir: URL
    let onProgress: (UUID, Int64, Int64) -> Void
    let onComplete: (UUID, URL?) -> Void
    let onError: (UUID, String) -> Void

    init(taskId: UUID,
         fileName: String,
         destinationDir: URL,
         onProgress: @escaping (UUID, Int64, Int64) -> Void,
         onComplete: @escaping (UUID, URL?) -> Void,
         onError: @escaping (UUID, String) -> Void) {
        self.taskId = taskId
        self.fileName = fileName
        self.destinationDir = destinationDir
        self.onProgress = onProgress
        self.onComplete = onComplete
        self.onError = onError
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        onProgress(taskId, totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // CRITICAL: This runs on the URLSession serial queue.
        // The file at `location` is DELETED by the system when this method returns.
        // We MUST copy it synchronously here, right now.

        let destination = destinationDir.appendingPathComponent(fileName)

        do {
            // Ensure dir exists
            try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)

            // Remove old file
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }

            // Copy the temp file to our destination
            try FileManager.default.copyItem(at: location, to: destination)

            onComplete(taskId, destination)
        } catch {
            onError(taskId, "File save failed: \(error.localizedDescription)")
        }
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if let error, (error as NSError).code != NSURLErrorCancelled {
            onError(taskId, error.localizedDescription)
        }
    }
}
