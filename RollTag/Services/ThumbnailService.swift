import AppKit
import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct MediaAnalysis {
    var thumbnail: NSImage?
    var phash: String?
    var duration: Double?
    var width: Int?
    var height: Int?
    var capturedAt: Date?
}

enum ThumbnailService {
    static let analyzeConcurrency = 2
    static let previewSize = CGSize(width: 480, height: 270)
    static let lazyPosterSize = CGSize(width: 320, height: 180)
    static let gridMaxEdge: CGFloat = 320
    static let storedThumbMaxEdge: CGFloat = 480
    static let playerMaxEdge: CGFloat = 1280
    private static let generationLock = NSLock()
    private static var deferGenerationFlag = false

    static var deferGeneration: Bool {
        get {
            generationLock.lock()
            defer { generationLock.unlock() }
            return deferGenerationFlag
        }
        set {
            generationLock.lock()
            deferGenerationFlag = newValue
            generationLock.unlock()
        }
    }

    static func analyze(url: URL, thumbnailURL: URL) async -> MediaAnalysis {
        let analysis: MediaAnalysis
        switch MediaKind.of(filename: url.lastPathComponent) {
        case .image:
            analysis = analyzeImage(url: url)
        case .audio:
            analysis = await analyzeAudio(url: url)
        case .video:
            analysis = await analyzeVideo(url: url)
        }
        if let image = analysis.thumbnail {
            writeThumbnail(image, to: thumbnailURL)
        }
        return analysis
    }

    static func thumbnailFileURL(warehouseRoot: URL, footageID: UUID) -> URL {
        warehouseRoot
            .appendingPathComponent(MediaConstants.rolltagDirectory)
            .appendingPathComponent(MediaConstants.thumbsDirectory)
            .appendingPathComponent("\(footageID.uuidString).jpg")
    }

    static func loadThumbnail(at url: URL, maxEdge: CGFloat = gridMaxEdge) -> NSImage? {
        stillImage(url: url, maxEdge: maxEdge, preferEmbedded: false)
    }

    static func previewStill(url: URL, maxEdge: CGFloat = playerMaxEdge) async -> NSImage? {
        await ThumbnailDecodeGate.shared.acquire()
        let image = await Task.detached(priority: .utility) { () -> NSImage? in
            stillImage(url: url, maxEdge: maxEdge, preferEmbedded: false)
        }.value
        await ThumbnailDecodeGate.shared.release()
        return image
    }

    static func ensureImageThumbnail(
        source: URL,
        thumbnailURL: URL,
        maxEdge: CGFloat = gridMaxEdge,
        allowCreate: Bool = true
    ) async -> NSImage? {
        let cacheKey = memoryKey(thumbnailURL, maxEdge: maxEdge)
        if let cached = ThumbnailMemoryCache.shared.image(for: cacheKey) {
            return cached
        }
        if let existing = loadThumbnail(at: thumbnailURL, maxEdge: maxEdge) {
            ThumbnailMemoryCache.shared.store(existing, for: cacheKey)
            return existing
        }
        guard allowCreate else { return nil }
        await ThumbnailDecodeGate.shared.acquire()
        let image = await Task.detached(priority: .utility) { () -> NSImage? in
            let storedEdge = min(max(maxEdge, gridMaxEdge), storedThumbMaxEdge)
            guard let stored = stillImage(url: source, maxEdge: storedEdge, preferEmbedded: true) else { return nil }
            writeThumbnail(stored, to: thumbnailURL)
            if maxEdge + 0.5 < storedEdge {
                return stillImage(url: thumbnailURL, maxEdge: maxEdge, preferEmbedded: false) ?? stored
            }
            return stored
        }.value
        await ThumbnailDecodeGate.shared.release()
        if let image {
            ThumbnailMemoryCache.shared.store(image, for: cacheKey)
        }
        return image
    }

    static func ensureVideoThumbnail(
        source: URL,
        thumbnailURL: URL,
        maxEdge: CGFloat = gridMaxEdge,
        allowCreate: Bool = true
    ) async -> NSImage? {
        let cacheKey = memoryKey(thumbnailURL, maxEdge: maxEdge)
        if let cached = ThumbnailMemoryCache.shared.image(for: cacheKey) {
            return cached
        }
        if let existing = loadThumbnail(at: thumbnailURL, maxEdge: maxEdge) {
            ThumbnailMemoryCache.shared.store(existing, for: cacheKey)
            return existing
        }
        guard allowCreate else { return nil }
        await ThumbnailDecodeGate.shared.acquire()
        let image = await Task.detached(priority: .utility) { () -> NSImage? in
            guard let stored = posterFallback(url: source) else { return nil }
            writeThumbnail(stored, to: thumbnailURL)
            if maxEdge + 0.5 < max(stored.size.width, stored.size.height) {
                return stillImage(url: thumbnailURL, maxEdge: maxEdge, preferEmbedded: false) ?? stored
            }
            return stored
        }.value
        await ThumbnailDecodeGate.shared.release()
        if let image {
            ThumbnailMemoryCache.shared.store(image, for: cacheKey)
        }
        return image
    }

    static func perceptualHash(_ image: NSImage) -> String {
        let side = 8
        guard let resized = grayscaleBitmap(image, width: side, height: side) else { return "" }
        let pixels = resized
        let average = pixels.reduce(0, +) / Double(pixels.count)
        var bits = ""
        for value in pixels {
            bits.append(value >= average ? "1" : "0")
        }
        return bits
    }

    static func shouldAnalyze(_ record: FootageSnapshot, thumbExists _: Bool) -> Bool {
        guard record.status == .available else { return false }
        switch MediaKind.of(filename: record.filename) {
        case .image:
            return record.needsReanalysis
        case .audio, .video:
            return record.needsReanalysis || record.duration == nil
        }
    }

    static func stillImage(url: URL, maxEdge: CGFloat = 768, preferEmbedded: Bool = true) -> NSImage? {
        let pixelSize = max(Int(maxEdge.rounded()), 1)
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions),
              CGImageSourceGetCount(source) > 0
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceCreateThumbnailFromImageAlways: !preferEmbedded,
            kCGImageSourceCreateThumbnailFromImageIfAbsent: preferEmbedded,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixelSize,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return nsImage(from: cg)
    }

    private static func memoryKey(_ url: URL, maxEdge: CGFloat) -> String {
        "\(url.path)#\(Int(maxEdge.rounded()))"
    }

    private static func nsImage(from cg: CGImage) -> NSImage {
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        image.cacheMode = .never
        return image
    }

    private static func analyzeImage(url: URL) -> MediaAnalysis {
        var width: Int?
        var height: Int?
        if let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            width = intValue(properties[kCGImagePropertyPixelWidth])
            height = intValue(properties[kCGImagePropertyPixelHeight])
        }
        return MediaAnalysis(
            thumbnail: nil,
            phash: nil,
            duration: nil,
            width: width,
            height: height,
            capturedAt: nil
        )
    }

    private static func analyzeAudio(url: URL) async -> MediaAnalysis {
        let duration = await loadedDuration(url)
        return MediaAnalysis(
            thumbnail: nil,
            phash: nil,
            duration: duration,
            width: nil,
            height: nil,
            capturedAt: nil
        )
    }

    private static func analyzeVideo(url: URL) async -> MediaAnalysis {
        let duration = await loadedDuration(url)
        return MediaAnalysis(
            thumbnail: nil,
            phash: nil,
            duration: duration,
            width: nil,
            height: nil,
            capturedAt: nil
        )
    }

    private static func loadedDuration(_ url: URL) async -> Double? {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
        let seconds = (try? await asset.load(.duration))?.seconds
        if let seconds, seconds.isFinite, seconds > 0 {
            return seconds
        }
        return nil
    }

    private static func posterFallback(url: URL) -> NSImage? {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = lazyPosterSize
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity
        let time = CMTime(seconds: 0, preferredTimescale: 600)
        guard let cg = try? generator.copyCGImage(at: time, actualTime: nil) else { return nil }
        return nsImage(from: cg)
    }

    private static func writeThumbnail(_ image: NSImage, to url: URL) {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return }
        CGImageDestinationAddImage(destination, cg, [kCGImageDestinationLossyCompressionQuality: 0.68] as CFDictionary)
        CGImageDestinationFinalize(destination)
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber: return number.intValue
        case let number as Int: return number
        default: return nil
        }
    }

    private static func grayscaleBitmap(_ image: NSImage, width: Int, height: Int) -> [Double]? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.interpolationQuality = .low
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels.map { Double($0) }
    }
}

final class ThumbnailMemoryCache: @unchecked Sendable {
    static let shared = ThumbnailMemoryCache()
    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 160
        cache.totalCostLimit = 40 * 1024 * 1024
    }

    func image(for key: String) -> NSImage? {
        cache.object(forKey: key as NSString)
    }

    func store(_ image: NSImage, for key: String) {
        let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        let cost = max(1, (cg?.width ?? 1) * (cg?.height ?? 1) * 4)
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }
}

actor ThumbnailDecodeGate {
    static let shared = ThumbnailDecodeGate()
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !busy {
            busy = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if waiters.isEmpty {
            busy = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
