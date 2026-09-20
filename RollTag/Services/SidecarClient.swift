import Foundation

final class SidecarClient {
    private var process: Process?
    private(set) var baseURL: URL?
    private let hasher = FileHasher()

    var isRunning: Bool { baseURL != nil }

    func start() {
        guard process == nil else { return }
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

        let stdout = Pipe()
        task.standardOutput = stdout
        task.standardError = Pipe()

        do {
            try task.run()
            process = task
            if let line = readReadyLine(from: stdout), let url = parseReady(line) {
                baseURL = url
            }
        } catch {
            process = nil
        }
    }

    func stop() {
        process?.terminate()
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
        context: [String: Any] = [:]
    ) async throws -> [String: Any] {
        guard let baseURL else {
            throw SidecarError.unavailable
        }
        var request = URLRequest(url: baseURL.appending(path: "suggest_tags"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "provider": provider.rawValue,
            "api_key": apiKey,
            "model": model,
            "frames": frames.map { $0.base64EncodedString() },
            "catalog": catalog,
            "context": context,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if status >= 400 {
            throw SidecarError.requestFailed(object["error"] as? String ?? "http_\(status)")
        }
        return object
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
