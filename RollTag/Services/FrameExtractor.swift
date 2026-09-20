import AppKit
import AVFoundation
import Foundation

enum FrameExtractor {
    static let defaultCount = 6
    static let maxEdge: CGFloat = 768

    static func sampleFractions(count: Int = defaultCount) -> [Double] {
        guard count > 1 else { return [0.5] }
        return (0..<count).map { index in
            let t = Double(index) / Double(count - 1)
            return 0.05 + t * 0.90
        }
    }

    static func jpegStills(url: URL, count: Int = defaultCount) async -> [Data] {
        if MediaKind.of(filename: url.lastPathComponent) == .image {
            return stillImageJPEG(url: url).map { [$0] } ?? []
        }
        if MediaKind.of(filename: url.lastPathComponent) == .audio {
            return []
        }

        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let duration = (try? await asset.load(.duration))?.seconds ?? 0
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxEdge, height: maxEdge)
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity

        let times: [Double]
        if duration.isFinite, duration > 0.05 {
            times = sampleFractions(count: count).map { fraction in
                min(max(duration * fraction, 0), max(duration - 0.04, 0))
            }
        } else {
            times = [0, 0.1, 1]
        }

        var frames: [Data] = []
        var seen = Set<Data>()
        for seconds in times {
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            guard let cg = try? generator.copyCGImage(at: time, actualTime: nil),
                  let data = jpeg(from: cg),
                  seen.insert(data).inserted
            else { continue }
            frames.append(data)
        }

        if frames.isEmpty, let fallback = stillImageJPEG(url: url) {
            frames = [fallback]
        }
        return frames
    }

    private static func stillImageJPEG(url: URL) -> Data? {
        guard let image = ThumbnailService.stillImage(url: url, maxEdge: maxEdge, preferEmbedded: false),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        return jpeg(from: cg)
    }

    private static func jpeg(from image: CGImage) -> Data? {
        let bitmap = NSBitmapImageRep(cgImage: image)
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
    }
}
