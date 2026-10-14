import Foundation

actor LocalAIInstaller {
    static let shared = LocalAIInstaller()

    private var inFlight: [LocalAIScheme: Task<Void, Error>] = [:]
    private var downloaders: [LocalAIScheme: FileDownload] = [:]

    func isDownloading(scheme: LocalAIScheme) -> Bool {
        inFlight[scheme] != nil
    }

    func ensureInstalled(
        scheme: LocalAIScheme,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        if LocalAIStore.isInstalled(scheme: scheme) {
            progress(1.0)
            return
        }

        if let existing = inFlight[scheme] {
            try await existing.value
            if !LocalAIStore.isInstalled(scheme: scheme) {
                throw AITagError.requestFailed("\(scheme.rawValue)_missing_model")
            }
            return
        }

        guard let sourceURL = LocalAIStore.downloadURL(for: scheme),
              let destURL = LocalAIStore.modelURL(for: scheme) else {
            throw AITagError.requestFailed("unsupported_scheme")
        }

        let task = Task {
            let folder = destURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var request = URLRequest(url: sourceURL)
            request.setValue("RollTag/1.0", forHTTPHeaderField: "User-Agent")
            let downloader = FileDownload()
            await registerDownloader(downloader, for: scheme)
            defer { Task { await removeDownloader(for: scheme) } }
            try await downloader.get(request, to: destURL, progress: progress)
            guard LocalAIStore.isInstalled(scheme: scheme) else {
                throw AITagError.requestFailed("\(scheme.rawValue)_download_failed")
            }
        }

        inFlight[scheme] = task
        defer { inFlight[scheme] = nil }
        try await task.value
    }

    func cancel(scheme: LocalAIScheme) {
        inFlight[scheme]?.cancel()
        inFlight[scheme] = nil
        downloaders[scheme]?.cancel()
        downloaders[scheme] = nil

        // Clean up partial downloads if not completed
        if let destURL = LocalAIStore.modelURL(for: scheme),
           FileManager.default.fileExists(atPath: destURL.path),
           !LocalAIStore.isInstalled(scheme: scheme) {
            try? FileManager.default.removeItem(at: destURL)
        }
    }

    private func registerDownloader(_ downloader: FileDownload, for scheme: LocalAIScheme) {
        downloaders[scheme] = downloader
    }

    private func removeDownloader(for scheme: LocalAIScheme) {
        downloaders[scheme] = nil
    }
}

private final class FileDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<Void, Error>?
    private var destination: URL?
    private var progress: (@Sendable (Double) -> Void)?
    private var finished = false
    private var session: URLSession?
    private var downloadTask: URLSessionDownloadTask?

    func get(
        _ request: URLRequest,
        to destination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        self.destination = destination
        self.progress = progress
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            continuation = cont
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 120
            configuration.timeoutIntervalForResource = 60 * 60 // 1 hour for larger models
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            self.session = session
            let task = session.downloadTask(with: request)
            self.downloadTask = task
            task.resume()
        }
    }

    func cancel() {
        guard !finished else { return }
        finished = true
        downloadTask?.cancel()
        session?.invalidateAndCancel()
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = min(1.0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        progress?(fraction)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let destination else {
            fail(AITagError.requestFailed("download_destination_missing"))
            return
        }
        do {
            if let http = downloadTask.response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw AITagError.requestFailed("http_\(http.statusCode)")
            }
            let folder = destination.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: location, to: destination)
        } catch {
            fail(error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            fail(error)
            return
        }
        finish()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        session?.finishTasksAndInvalidate()
        continuation?.resume()
        continuation = nil
    }

    private func fail(_ error: Error) {
        guard !finished else { return }
        finished = true
        session?.invalidateAndCancel()
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
