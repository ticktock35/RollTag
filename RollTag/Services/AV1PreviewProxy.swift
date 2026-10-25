import CryptoKit
import Foundation

enum MatroskaVideoCodec: Equatable {
    case av1
    case vp9
    case vp8
    case other
}

enum MatroskaSniff {
    private static let lock = NSLock()
    private static var cache: [String: MatroskaVideoCodec] = [:]

    static func videoCodec(in data: Data) -> MatroskaVideoCodec {
        if data.range(of: Data("V_AV1".utf8)) != nil { return .av1 }
        if data.range(of: Data("V_VP9".utf8)) != nil { return .vp9 }
        if data.range(of: Data("V_VP8".utf8)) != nil { return .vp8 }
        return .other
    }

    static func videoCodec(of url: URL) -> MatroskaVideoCodec {
        let key = cacheKey(for: url)
        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let codec = videoCodec(in: header(of: url))
        lock.lock()
        cache[key] = codec
        lock.unlock()
        return codec
    }

    private static func header(of url: URL) -> Data {
        guard let handle = FileHandle(forReadingAtPath: url.path) else { return Data() }
        defer { try? handle.close() }
        return handle.readData(ofLength: 256 * 1024)
    }

    private static func cacheKey(for url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let size = values?.fileSize ?? 0
        let mtime = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        return "\(url.path)|\(size)|\(mtime)"
    }
}

enum AV1PreviewLog {
    static func parseClock(_ text: Substring) -> Double? {
        let token = text.prefix { $0.isNumber || $0 == ":" || $0 == "." }
        let parts = token.split(separator: ":")
        guard parts.count == 3,
              let hours = Double(parts[0]),
              let minutes = Double(parts[1]),
              let seconds = Double(parts[2]) else { return nil }
        return hours * 3600 + minutes * 60 + seconds
    }

    static func parse(line: String) -> (duration: Double?, encoded: Double?) {
        var duration: Double?
        var encoded: Double?
        if let range = line.range(of: "Duration: ") {
            duration = parseClock(line[range.upperBound...])
        }
        if let range = line.range(of: "time=") {
            encoded = parseClock(line[range.upperBound...])
        }
        return (duration, encoded)
    }
}

enum AV1PreviewProxy {
    /// Tests set this false so selecting a fake AV1 file does not spawn ffmpeg.
    static var automaticallyStartsJobs = true

    static let maxEdge = 1280

    static func needsProxy(for url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard ext == "webm" || ext == "mkv" else { return false }
        return MatroskaSniff.videoCodec(of: url) == .av1
    }

    static func ffmpegURL(candidates: [String]? = nil) -> URL? {
        let defaults = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
        ]
        let env = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let fromPath = env.split(separator: ":").map { "\($0)/ffmpeg" }
        for path in (candidates ?? defaults + fromPath) {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    static func arguments(source: URL, output: URL) -> [String] {
        [
            "-hide_banner", "-y",
            "-i", source.path,
            "-map", "0:v:0",
            "-map", "0:a:0?",
            "-vf", "scale=min(\(maxEdge)\\,iw):-2:force_original_aspect_ratio=decrease",
            "-c:v", "h264_videotoolbox",
            "-b:v", "3500k",
            "-allow_sw", "1",
            "-pix_fmt", "yuv420p",
            "-c:a", "aac",
            "-ac", "2",
            "-b:a", "160k",
            "-movflags", "frag_keyframe+empty_moov+default_base_moof",
            "-f", "mp4",
            output.path,
        ]
    }

    static func cacheURL(for source: URL) throws -> URL {
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RollTag/av1-preview", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let values = try source.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let size = values.fileSize ?? 0
        let mtime = Int(values.contentModificationDate?.timeIntervalSince1970 ?? 0)
        let key = Data("\(source.path)|\(size)|\(mtime)".utf8)
        let digest = SHA256.hash(data: key).map { String(format: "%02x", $0) }.joined()
        return folder.appendingPathComponent("\(digest).mp4")
    }

    static func isFinished(_ output: URL) -> Bool {
        FileManager.default.fileExists(atPath: output.path)
            && FileManager.default.fileExists(atPath: doneMarker(for: output).path)
    }

    static func doneMarker(for output: URL) -> URL {
        output.appendingPathExtension("done")
    }
}

@MainActor
final class AV1PreviewJob {
    private(set) var isComplete = false
    private(set) var outputURL: URL?
    private var process: Process?
    private var cancelled = false
    private var reportedPlayable = false
    private var pendingLine = ""

    func start(
        source: URL,
        onDuration: @escaping (Double) -> Void,
        onProgress: @escaping (Double) -> Void,
        onPlayable: @escaping (URL) -> Void,
        onFinished: @escaping (URL) -> Void,
        onFailed: @escaping () -> Void
    ) {
        let output: URL
        do {
            output = try AV1PreviewProxy.cacheURL(for: source)
        } catch {
            onFailed()
            return
        }
        outputURL = output
        if AV1PreviewProxy.isFinished(output) {
            isComplete = true
            reportedPlayable = true
            onPlayable(output)
            onFinished(output)
            return
        }
        guard let ffmpeg = AV1PreviewProxy.ffmpegURL() else {
            onFailed()
            return
        }
        try? FileManager.default.removeItem(at: output)
        try? FileManager.default.removeItem(at: AV1PreviewProxy.doneMarker(for: output))
        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = AV1PreviewProxy.arguments(source: source, output: output)
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self?.consume(text, output: output, onDuration: onDuration, onProgress: onProgress, onPlayable: onPlayable)
            }
        }
        process.terminationHandler = { [weak self] process in
            Task { @MainActor in
                guard let self, !self.cancelled else { return }
                pipe.fileHandleForReading.readabilityHandler = nil
                if process.terminationStatus == 0, FileManager.default.fileExists(atPath: output.path) {
                    try? Data("ok".utf8).write(to: AV1PreviewProxy.doneMarker(for: output))
                    self.isComplete = true
                    if !self.reportedPlayable {
                        self.reportedPlayable = true
                        onPlayable(output)
                    }
                    onFinished(output)
                } else {
                    onFailed()
                }
            }
        }
        self.process = process
        do {
            try process.run()
        } catch {
            onFailed()
        }
    }

    func cancel() {
        cancelled = true
        process?.terminationHandler = nil
        if let pipe = process?.standardError as? Pipe {
            pipe.fileHandleForReading.readabilityHandler = nil
        }
        process?.terminate()
        process = nil
    }

    private func consume(
        _ text: String,
        output: URL,
        onDuration: (Double) -> Void,
        onProgress: (Double) -> Void,
        onPlayable: (URL) -> Void
    ) {
        pendingLine.append(text)
        while let newline = pendingLine.firstIndex(where: { $0 == "\n" || $0 == "\r" }) {
            let line = String(pendingLine[..<newline])
            pendingLine = String(pendingLine[pendingLine.index(after: newline)...])
            let parsed = AV1PreviewLog.parse(line: line)
            if let duration = parsed.duration {
                onDuration(duration)
            }
            if let encoded = parsed.encoded {
                onProgress(encoded)
                if !reportedPlayable, encoded >= 0.4, FileManager.default.fileExists(atPath: output.path) {
                    reportedPlayable = true
                    onPlayable(output)
                }
            }
        }
    }
}
