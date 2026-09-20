import AVFoundation
import Foundation

enum TrimService {
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

        FileManager.default.createFile(atPath: destination.path, contents: nil)
        try? FileManager.default.removeItem(at: destination)

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
