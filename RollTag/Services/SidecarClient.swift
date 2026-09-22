import Darwin
import Foundation

final class SidecarClient {
    private var process: Process?
    private var stdinPipe: Pipe?
    private(set) var baseURL: URL?
    private let hasher = FileHasher()
    private var suggestTask: Task<[String: Any], Error>?
    private var suggestGeneration = 0

    var isRunning: Bool { baseURL != nil }

    func start() {
        if let process, process.isRunning { return }
        stop()
        guard let sidecarRoot = Bundle.main.resourceURL?.appendingPathComponent("sidecar"),
              FileManager.default.fileExists(atPath: sidecarRoot.path)
        else {
            return
        }

        let python = ["/usr/bin/python3", "/usr/local/bin/python3", "/opt/homebrew/bin/python3"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            ?? "/usr/bin/python3"

        let task = Process()
        task.executableURL = URL(fileURLWithPath: python)
        task.arguments = ["-m", "rolltag_sidecar"]
        task.currentDirectoryURL = sidecarRoot

        let stdin = Pipe()
        let stdout = Pipe()
        task.standardInput = stdin
        task.standardOutput = stdout
        task.standardError = Pipe()
        task.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.process == task else { return }
                self.process = nil
                self.stdinPipe = nil
                self.baseURL = nil
            }
        }

        do {
            try task.run()
            process = task
            stdinPipe = stdin
            if let line = readReadyLine(from: stdout), let url = parseReady(line) {
                baseURL = url
            }
        } catch {
            process = nil
            stdinPipe = nil
        }
    }

    func stop() {
        if let handle = stdinPipe?.fileHandleForWriting {
            try? handle.close()
        }
        stdinPipe = nil
        if let task = process, task.isRunning {
            task.terminate()
            let deadline = Date().addingTimeInterval(1)
            while task.isRunning, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.02)
            }
            if task.isRunning {
                kill(task.processIdentifier, SIGKILL)
            }
            task.waitUntilExit()
        }
        process = nil
        baseURL = nil
    }

    func hashFile(at url: URL) throws -> String {
        if let baseURL, let remote = try? remoteHash(path: url.path, baseURL: baseURL) {
            return remote
        }
        return try hasher.hashFile(at: url)
    }

    func reservedEmbed() -> String { "not_enabled" }

    func suggestTags(
        provider: AIProvider,
        apiKey: String,
        model: String,
        frames: [Data],
        catalog: [String: Any],
        context: [String: Any] = [:],
        examples: [AITaggingExample] = []
    ) async throws -> [String: Any] {
        guard let baseURL else {
            throw SidecarError.unavailable
        }
        var request = URLRequest(url: baseURL.appending(path: "suggest_tags"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        var body: [String: Any] = [
            "provider": provider.rawValue,
            "api_key": apiKey,
            "model": model,
            "frames": frames.map { $0.base64EncodedString() },
            "catalog": catalog,
            "context": context,
        ]
        let examplePayload = AITaggingExample.payloadList(examples)
        if !examplePayload.isEmpty {
            body["examples"] = examplePayload
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        suggestGeneration += 1
        let token = suggestGeneration
        let task = Task { () -> [String: Any] in
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            if status >= 400 {
                throw SidecarError.requestFailed(object["error"] as? String ?? "http_\(status)")
            }
            return object
        }
        suggestTask = task
        defer {
            if suggestGeneration == token {
                suggestTask = nil
            }
        }
        do {
            return try await task.value
        } catch {
            if AITaggingStop.isCancellation(error) {
                throw CancellationError()
            }
            throw error
        }
    }

    func cancelInFlightSuggest() {
        suggestGeneration += 1
        suggestTask?.cancel()
        suggestTask = nil
    }

    private func remoteHash(path: String, baseURL: URL) throws -> String {
        var request = URLRequest(url: baseURL.appending(path: "hash"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["path": path])
        request.timeoutInterval = 30
        let semaphore = DispatchSemaphore(value: 0)
        var captured: Result<[String: Any], Error> = .failure(URLError(.timedOut))
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error {
                captured = .failure(error)
            } else if let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                captured = .success(object)
            } else {
                captured = .failure(URLError(.cannotParseResponse))
            }
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 30)
        let object = try captured.get()
        guard let hash = object["content_hash"] as? String else {
            throw URLError(.cannotParseResponse)
        }
        return hash
    }

    private func readReadyLine(from pipe: Pipe) -> String? {
        let handle = pipe.fileHandleForReading
        let deadline = Date().addingTimeInterval(2)
        var buffer = Data()
        while Date() < deadline {
            let chunk = handle.availableData
            if !chunk.isEmpty {
                buffer.append(chunk)
                if let text = String(data: buffer, encoding: .utf8), text.contains("\n") {
                    return text.split(separator: "\n").first.map(String.init)
                }
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return String(data: buffer, encoding: .utf8)
    }

    private func parseReady(_ line: String) -> URL? {
        let parts = line.split(separator: " ")
        guard parts.count >= 2, parts[0] == "READY" else { return nil }
        return URL(string: "http://\(parts[1])")
    }
}

enum SidecarError: LocalizedError {
    case unavailable
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            String(localized: "ai.sidecarUnavailable")
        case .requestFailed(let message):
            message
        }
    }
}
