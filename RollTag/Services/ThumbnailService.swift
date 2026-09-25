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
        decodeStill(url: url, maxEdge: maxEdge)
    }

    static func jpegData(from image: CGImage, maxEdge: CGFloat, quality: Double = 0.7) -> Data? {
        let size = jpegPixelSize(image, maxEdge: max(Int(maxEdge.rounded()), 1))
        guard let cg = rasterizeOpaque(image, width: size.width, height: size.height) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(
            destination,
            cg,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    static func removeStoredThumbnail(at url: URL) {
        try? FileManager.default.removeItem(at: url)
        ThumbnailMemoryCache.shared.remove(thumbnailURL: url)
    }

    static func sweepOrphanThumbnails(in directory: URL, keep: Set<UUID>) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }
        for file in files where file.pathExtension.lowercased() == "jpg" {
            let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent)
            if id == nil || keep.contains(id!) == false {
                removeStoredThumbnail(at: file)
            }
        }
    }

    static func previewStill(url: URL, maxEdge: CGFloat = playerMaxEdge) async -> NSImage? {
        await Task.detached(priority: .userInitiated) { () -> NSImage? in
            stillImage(url: url, maxEdge: maxEdge, preferEmbedded: true)
                ?? stillImage(url: url, maxEdge: maxEdge, preferEmbedded: false)
        }.value
    }

    static func ensureImageThumbnail(
        source: URL,
        thumbnailURL: URL,
        maxEdge: CGFloat = gridMaxEdge,
        allowCreate: Bool = true
    ) async -> NSImage? {
        if !FileManager.default.fileExists(atPath: source.path) {
            removeStoredThumbnail(at: thumbnailURL)
            return nil
        }
        let cacheKey = memoryKey(thumbnailURL, maxEdge: maxEdge)
        if let cached = ThumbnailMemoryCache.shared.image(for: cacheKey),
           thumbnailMatchesSourceAspect(cached, source: source) {
            return cached
        }
        if let existing = loadThumbnail(at: thumbnailURL, maxEdge: maxEdge),
           thumbnailMatchesSourceAspect(existing, source: source) {
            ThumbnailMemoryCache.shared.store(existing, for: cacheKey)
            return existing
        }
        if FileManager.default.fileExists(atPath: thumbnailURL.path) {
            removeStoredThumbnail(at: thumbnailURL)
        }
        guard allowCreate else { return nil }
        await ThumbnailDecodeGate.shared.acquire()
        let image = await Task.detached(priority: .utility) { () -> NSImage? in
            let storedEdge = min(max(maxEdge, gridMaxEdge), storedThumbMaxEdge)
            guard let stored = decodeStill(url: source, maxEdge: storedEdge, preferEmbedded: false) else { return nil }
            writeThumbnail(stored, to: thumbnailURL)
            if maxEdge + 0.5 < storedEdge {
                return decodeStill(url: thumbnailURL, maxEdge: maxEdge) ?? stored
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
        if !FileManager.default.fileExists(atPath: source.path) {
            removeStoredThumbnail(at: thumbnailURL)
            return nil
        }
        let cacheKey = memoryKey(thumbnailURL, maxEdge: maxEdge)
        if let cached = ThumbnailMemoryCache.shared.image(for: cacheKey),
           thumbnailMatchesSourceAspect(cached, source: source) {
            return cached
        }
        if let existing = loadThumbnail(at: thumbnailURL, maxEdge: maxEdge),
           thumbnailMatchesSourceAspect(existing, source: source) {
            ThumbnailMemoryCache.shared.store(existing, for: cacheKey)
            return existing
        }
        if FileManager.default.fileExists(atPath: thumbnailURL.path) {
            removeStoredThumbnail(at: thumbnailURL)
        }
        guard allowCreate else { return nil }
        await ThumbnailDecodeGate.shared.acquire()
        let image = await Task.detached(priority: .utility) { () -> NSImage? in
            let storedEdge = min(max(maxEdge, gridMaxEdge), storedThumbMaxEdge)
            guard let stored = posterFallback(url: source, maxEdge: storedEdge) else { return nil }
            writeThumbnail(stored, to: thumbnailURL)
            if maxEdge + 0.5 < max(stored.size.width, stored.size.height) {
                return decodeStill(url: thumbnailURL, maxEdge: maxEdge) ?? stored
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

    static func stillImage(url: URL, maxEdge: CGFloat = 768, preferEmbedded: Bool = false) -> NSImage? {
        decodeStill(url: url, maxEdge: maxEdge, preferEmbedded: preferEmbedded)
    }

    static func decodeStill(url: URL, maxEdge: CGFloat, preferEmbedded: Bool = false) -> NSImage? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        if preferEmbedded, let image = imageSourceThumbnail(url: url, maxEdge: maxEdge, preferEmbedded: true) {
            return image
        }
        if let image = imageSourceThumbnail(url: url, maxEdge: maxEdge, preferEmbedded: false) {
            return image
        }
        guard let original = NSImage(contentsOf: url) else { return nil }
        return downscale(original, maxEdge: maxEdge) ?? original
    }

    /// Pixel size after EXIF/TIFF orientation (iPhone portrait is often stored landscape).
    static func orientedPixelSize(url: URL) -> (width: Int, height: Int)? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options)
            ?? mappedImageSource(url: url, options: options),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = intValue(properties[kCGImagePropertyPixelWidth]),
              let height = intValue(properties[kCGImagePropertyPixelHeight])
        else { return nil }
        let orientation = intValue(properties[kCGImagePropertyOrientation]) ?? 1
        return displaySize(width: width, height: height, orientation: orientation)
    }

    static func displaySize(width: Int, height: Int, orientation: Int) -> (width: Int, height: Int) {
        switch orientation {
        case 5, 6, 7, 8:
            return (height, width)
        default:
            return (width, height)
        }
    }

    /// Display size after the video track's preferred transform (phone portrait is often stored landscape).
    static func displaySize(naturalSize: CGSize, preferredTransform: CGAffineTransform) -> (width: Int, height: Int) {
        let rendered = naturalSize.applying(preferredTransform)
        return (
            width: max(1, Int(abs(rendered.width).rounded())),
            height: max(1, Int(abs(rendered.height).rounded()))
        )
    }

    static func orientedVideoSize(url: URL) -> (width: Int, height: Int)? {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
        guard let track = asset.tracks(withMediaType: .video).first else { return nil }
        let size = displaySize(naturalSize: track.naturalSize, preferredTransform: track.preferredTransform)
        guard size.width > 0, size.height > 0 else { return nil }
        return size
    }

    static func orientedMediaSize(url: URL) -> (width: Int, height: Int)? {
        switch MediaKind.of(filename: url.lastPathComponent) {
        case .image:
            return orientedPixelSize(url: url)
        case .video:
            return orientedVideoSize(url: url)
        case .audio:
            return nil
        }
    }

    private static func imageSourceThumbnail(url: URL, maxEdge: CGFloat, preferEmbedded: Bool) -> NSImage? {
        let pixelSize = max(Int(maxEdge.rounded()), 1)
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions)
            ?? mappedImageSource(url: url, options: sourceOptions)
        guard let source, CGImageSourceGetCount(source) > 0 else { return nil }
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

    private static func mappedImageSource(url: URL, options: CFDictionary) -> CGImageSource? {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return nil }
        return CGImageSourceCreateWithData(data as CFData, options)
    }

    private static func downscale(_ image: NSImage, maxEdge: CGFloat) -> NSImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let size = jpegPixelSize(cg, maxEdge: max(Int(maxEdge.rounded()), 1))
        guard let resized = rasterizeOpaque(cg, width: size.width, height: size.height) else { return nil }
        return nsImage(from: resized)
    }

    private static func thumbnailMatchesSourceAspect(_ thumbnail: NSImage, source: URL) -> Bool {
        guard let oriented = orientedMediaSize(url: source),
              oriented.width > 0,
              oriented.height > 0,
              let cg = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil),
              cg.width > 0,
              cg.height > 0
        else { return true }
        let thumbAspect = CGFloat(cg.width) / CGFloat(cg.height)
        let sourceAspect = CGFloat(oriented.width) / CGFloat(oriented.height)
        return abs(thumbAspect - sourceAspect) / max(sourceAspect, 0.01) < 0.12
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
        let size = orientedPixelSize(url: url)
        return MediaAnalysis(
            thumbnail: nil,
            phash: nil,
            duration: nil,
            width: size?.width,
            height: size?.height,
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
        let size = orientedVideoSize(url: url)
        return MediaAnalysis(
            thumbnail: nil,
            phash: nil,
            duration: duration,
            width: size?.width,
            height: size?.height,
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

    private static func posterFallback(url: URL, maxEdge: CGFloat = storedThumbMaxEdge) -> NSImage? {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let edge = max(maxEdge, 1)
        generator.maximumSize = CGSize(width: edge, height: edge)
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity
        let time = CMTime(seconds: 0, preferredTimescale: 600)
        guard let cg = try? generator.copyCGImage(at: time, actualTime: nil) else { return nil }
        return nsImage(from: cg)
    }

    private static func writeThumbnail(_ image: NSImage, to url: URL) {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let data = jpegData(from: source, maxEdge: storedThumbMaxEdge, quality: 0.68)
        else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// JPEG has no alpha. Writing premultiplied RGBA makes ImageIO keep a 2× decode buffer.
    private static func rasterizeOpaque(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private static func jpegPixelSize(_ image: CGImage, maxEdge: Int) -> (width: Int, height: Int) {
        let longest = max(image.width, image.height)
        guard longest > maxEdge, maxEdge > 0 else {
            return (image.width, image.height)
        }
        let scale = CGFloat(maxEdge) / CGFloat(longest)
        return (
            max(1, Int((CGFloat(image.width) * scale).rounded())),
            max(1, Int((CGFloat(image.height) * scale).rounded()))
        )
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

    func remove(thumbnailURL: URL) {
        for edge in [64, 180, 320, 480, 768, 1280] {
            cache.removeObject(forKey: "\(thumbnailURL.path)#\(edge)" as NSString)
        }
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
