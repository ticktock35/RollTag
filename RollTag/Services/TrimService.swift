import AppKit
import AVFoundation
import Foundation

enum TrimService {
    static let minimumDuration = 0.2
    static let filmstripCount = 16

    static func exportClip(
        source: URL,
        destination: URL,
        start: Double,
        end: Double
    ) async throws {
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration)
        let startTime = CMTime(seconds: max(0, start), preferredTimescale: 600)
        let endTime = CMTime(seconds: min(end, duration.seconds), preferredTimescale: 600)
        let range = CMTimeRange(start: startTime, end: endTime)

        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw TrimError.exportUnavailable
        }
        session.outputURL = destination
        session.outputFileType = inferredFileType(for: destination)
        session.timeRange = range
        await session.export()
        if session.status != .completed {
            throw TrimError.failed(session.error?.localizedDescription ?? "export failed")
        }
    }

    static func sanitizedFilename(_ raw: String, fallback: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        name = name.replacingOccurrences(of: "/", with: "-")
        name = name.replacingOccurrences(of: ":", with: "-")
        name = name.replacingOccurrences(of: "\\", with: "-")
        if name.isEmpty {
            name = fallback
        }
        if (name as NSString).pathExtension.isEmpty {
            name += ".mp4"
        }
        return name
    }

    static func isSafeFolder(_ folder: String) -> Bool {
        let parts = WarehouseFolderTree.normalize(folder).split(separator: "/")
        return !parts.contains { $0.hasPrefix(".") }
    }

    static func relativePath(folder: String, filename: String) -> String {
        let dir = WarehouseFolderTree.normalize(folder)
        let name = sanitizedFilename(filename, fallback: "clip.mp4")
        return dir.isEmpty ? name : "\(dir)/\(name)"
    }

    static func warehouseRelativePath(of url: URL, warehouseRoot: URL) -> String? {
        let root = warehouseRoot.standardizedFileURL.resolvingSymlinksInPath().path
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        if path == root { return nil }
        guard path.hasPrefix(root + "/") else { return nil }
        let relative = String(path.dropFirst(root.count + 1))
        let folder = (relative as NSString).deletingLastPathComponent
        guard isSafeFolder(folder == "." ? "" : folder) else { return nil }
        return WarehouseFolderTree.normalize(relative)
    }

    static func uniqueRelativePath(root: URL, folder: String, filename: String) -> String {
        let safeFolder = isSafeFolder(folder) ? folder : ""
        let name = sanitizedFilename(filename, fallback: "clip.mp4")
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var index = 1
        while true {
            let candidate = index == 1 ? name : "\(base)_\(index).\(ext)"
            let relative = relativePath(folder: safeFolder, filename: candidate)
            let url = root.appendingPathComponent(relative)
            if !FileManager.default.fileExists(atPath: url.path) {
                return relative
            }
            index += 1
        }
    }

    static func defaultFilename(from source: String) -> String {
        let base = (source as NSString).deletingPathExtension
        let fallback = base.isEmpty ? "clip" : base
        return "\(fallback)_cut.mp4"
    }

    /// If playback left the in/out range, return the time to jump back to (the in point).
    static func loopPlayhead(current: Double, start: Double, end: Double) -> Double? {
        let lower = min(start, end)
        let upper = max(start, end)
        if current < lower - 0.02 || reachedOutPoint(current: current, end: upper) {
            return lower
        }
        return nil
    }

    static func reachedOutPoint(current: Double, end: Double) -> Bool {
        current >= end - 0.001
    }

    static func clampRange(start: Double, end: Double, duration: Double) -> (start: Double, end: Double) {
        let limit = max(duration, minimumDuration)
        var nextStart = min(max(0, start), max(0, limit - minimumDuration))
        var nextEnd = min(max(nextStart + minimumDuration, end), limit)
        if nextEnd - nextStart < minimumDuration {
            nextEnd = min(limit, nextStart + minimumDuration)
            nextStart = max(0, nextEnd - minimumDuration)
        }
        return (nextStart, nextEnd)
    }

    static func filmstrip(url: URL, duration: Double, count: Int = filmstripCount) async -> [NSImage] {
        let frames = max(count, 2)
        let length = max(duration, minimumDuration)
        return await Task.detached(priority: .utility) { () -> [NSImage] in
            let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 160, height: 90)
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.25, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.25, preferredTimescale: 600)
            var images: [NSImage] = []
            for index in 0..<frames {
                let seconds = length * (Double(index) + 0.5) / Double(frames)
                let time = CMTime(seconds: seconds, preferredTimescale: 600)
                guard let cg = try? generator.copyCGImage(at: time, actualTime: nil) else { continue }
                images.append(NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)))
            }
            return images
        }.value
    }

    private static func inferredFileType(for url: URL) -> AVFileType {
        switch url.pathExtension.lowercased() {
        case "mov": return .mov
        case "m4v": return .m4v
        default: return .mp4
        }
    }
}

enum TrimError: Error, LocalizedError {
    case exportUnavailable
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .exportUnavailable: return String(localized: "trim.unavailable")
        case .failed(let message): return message
        }
    }
}
