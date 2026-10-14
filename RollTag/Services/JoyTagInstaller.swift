import Foundation

actor JoyTagInstaller {
    static let shared = JoyTagInstaller()

    private var inFlight: Task<Void, Error>?

    func ensureInstalled(progress: @escaping @Sendable (Double) -> Void) async throws {
        if JoyTagStore.isInstalled { return }
        if let inFlight {
            try await inFlight.value
            if !JoyTagStore.isInstalled {
                throw AITagError.requestFailed("joytag_missing_model")
            }
            return
        }
        let task = Task {
            try await Self.download(progress: progress)
        }
        inFlight = task
        defer { inFlight = nil }
        try await task.value
    }

    func cancel() {
        inFlight?.cancel()
        inFlight = nil
    }

    private static func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        try FileManager.default.createDirectory(at: JoyTagStore.root, withIntermediateDirectories: true)
        try await download(
            url: JoyTagStore.huggingfaceURL("model.onnx"),
            destination: JoyTagStore.modelURL,
            progress: { fraction in progress(fraction * 0.98) }
        )
        try Task.checkCancellation()
        try await download(
            url: JoyTagStore.huggingfaceURL("top_tags.txt"),
            destination: JoyTagStore.tagsURL,
            progress: { fraction in progress(0.98 + fraction * 0.02) }
        )
        progress(1)
        guard JoyTagStore.isInstalled else {
            throw AITagError.requestFailed("joytag_missing_model")
        }
    }

    private static func download(
        url: URL,
        destination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        var request = URLRequest(url: url)
        request.setValue("RollTag/1.0", forHTTPHeaderField: "User-Agent")
        let downloader = FileDownload()
        try await downloader.get(request, to: destination, progress: progress)
    }
}

private final class FileDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<Void, Error>?
    private var destination: URL?
    private var progress: (@Sendable (Double) -> Void)?
    private var finished = false
    private var session: URLSession?

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
            configuration.timeoutIntervalForResource = 60 * 30
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            self.session = session
            session.downloadTask(with: request).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress?(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let destination else {
            fail(AITagError.requestFailed("joytag_download"))
            return
        }
        do {
            if let http = downloadTask.response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw AITagError.requestFailed("joytag_http_\(http.statusCode)")
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
