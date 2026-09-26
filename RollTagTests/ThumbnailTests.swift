import AppKit
import ImageIO
import XCTest
@testable import RollTag

final class ThumbnailTests: XCTestCase {
    func testStillImageDownsamplesToMaxEdge() throws {
        let source = try writePNG(width: 1200, height: 900)
        let image = ThumbnailService.stillImage(url: source, maxEdge: 80, preferEmbedded: false)
        let size = pixelSize(image)
        XCTAssertNotNil(image)
        XCTAssertLessThanOrEqual(max(size.width, size.height), 80)
    }

    func testLoadThumbnailDoesNotKeepFullStoredPixels() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rolltag-thumb-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let source = try writePNG(width: 1000, height: 1000, in: dir)
        let dest = dir.appendingPathComponent("thumb.jpg")
        let stored = await ThumbnailService.ensureImageThumbnail(
            source: source,
            thumbnailURL: dest,
            maxEdge: 480
        )
        XCTAssertNotNil(stored)
        let grid = ThumbnailService.loadThumbnail(at: dest, maxEdge: 64)
        let size = pixelSize(grid)
        XCTAssertLessThanOrEqual(max(size.width, size.height), 64)
    }

    func testAIFrameJPEGHasNoAlpha() throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: 1200,
            height: 675,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return XCTFail("could not make premul source")
        }
        context.setFillColor(CGColor(red: 0.1, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1200, height: 675))
        guard let source = context.makeImage(),
              let data = ThumbnailService.jpegData(from: source, maxEdge: 768, quality: 0.7)
        else {
            return XCTFail("jpegData failed")
        }
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, options),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
        else {
            return XCTFail("encoded frame is not readable JPEG")
        }
        XCTAssertNotEqual(properties[kCGImagePropertyHasAlpha] as? Bool, true)
        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        XCTAssertLessThanOrEqual(max(width, height), 768)
        XCTAssertGreaterThan(min(width, height), 0)
    }

    func testStoredThumbnailJPEGHasNoAlphaAndStaysWithinStoredEdge() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rolltag-opaque-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let source = try writePNG(width: 1600, height: 900, in: dir)
        let dest = dir.appendingPathComponent("thumb.jpg")
        _ = await ThumbnailService.ensureImageThumbnail(source: source, thumbnailURL: dest, maxEdge: 320)
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithURL(dest as CFURL, options),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
        else {
            return XCTFail("stored thumbnail is not readable JPEG")
        }
        XCTAssertNotEqual(properties[kCGImagePropertyHasAlpha] as? Bool, true)
        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        XCTAssertLessThanOrEqual(max(width, height), Int(ThumbnailService.storedThumbMaxEdge))
        XCTAssertGreaterThan(min(width, height), 0)
    }

    func testEnsureCreatesThumbnailWhenCacheMissing() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rolltag-make-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let source = try writePNG(width: 640, height: 480, in: dir)
        let dest = dir.appendingPathComponent("thumb.jpg")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path))
        let image = await ThumbnailService.ensureImageThumbnail(source: source, thumbnailURL: dest, maxEdge: 320)
        XCTAssertNotNil(image)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path))
    }

    func testMissingOriginalDeletesStoredThumbnail() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rolltag-gone-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let source = try writePNG(width: 200, height: 200, in: dir)
        let dest = dir.appendingPathComponent("thumb.jpg")
        _ = await ThumbnailService.ensureImageThumbnail(source: source, thumbnailURL: dest, maxEdge: 160)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path))
        try FileManager.default.removeItem(at: source)
        let image = await ThumbnailService.ensureImageThumbnail(source: source, thumbnailURL: dest, maxEdge: 160)
        XCTAssertNil(image)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path))
    }

    func testSweepRemovesOrphanThumbnails() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rolltag-sweep-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let keep = UUID()
        let drop = UUID()
        try Data([0xFF, 0xD8, 0xFF]).write(to: dir.appendingPathComponent("\(keep.uuidString).jpg"))
        try Data([0xFF, 0xD8, 0xFF]).write(to: dir.appendingPathComponent("\(drop.uuidString).jpg"))
        ThumbnailService.sweepOrphanThumbnails(in: dir, keep: [keep])
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(keep.uuidString).jpg").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(drop.uuidString).jpg").path))
    }

    func testVideoDisplaySizeAppliesPreferredTransform() {
        let stored = CGSize(width: 1920, height: 1080)
        let landscape = ThumbnailService.displaySize(naturalSize: stored, preferredTransform: .identity)
        XCTAssertEqual(landscape.width, 1920)
        XCTAssertEqual(landscape.height, 1080)
        let portrait = ThumbnailService.displaySize(
            naturalSize: stored,
            preferredTransform: CGAffineTransform(rotationAngle: .pi / 2)
        )
        XCTAssertEqual(portrait.width, 1080)
        XCTAssertEqual(portrait.height, 1920)
    }

    func testOrientedPixelSizeSwapsIPhonePortraitDimensions() {
        let upright = ThumbnailService.displaySize(width: 4032, height: 3024, orientation: 1)
        XCTAssertEqual(upright.width, 4032)
        XCTAssertEqual(upright.height, 3024)
        let rotated = ThumbnailService.displaySize(width: 4032, height: 3024, orientation: 6)
        XCTAssertEqual(rotated.width, 3024)
        XCTAssertEqual(rotated.height, 4032)
    }

    func testStillImageAppliesExifOrientationSoPortraitStaysUpright() throws {
        let source = try writeJPEG(width: 80, height: 40, orientation: 6)
        let sized = ThumbnailService.orientedPixelSize(url: source)
        XCTAssertEqual(sized?.width, 40)
        XCTAssertEqual(sized?.height, 80)
        let image = ThumbnailService.stillImage(url: source, maxEdge: 80, preferEmbedded: false)
        let size = pixelSize(image)
        XCTAssertGreaterThan(size.height, size.width)
    }

    func testEnsureReplacesStoredThumbWhenAspectIgnoresOrientation() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rolltag-orient-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let source = try writeJPEG(width: 80, height: 40, orientation: 6, in: dir)
        let dest = dir.appendingPathComponent("thumb.jpg")
        let wrong = try writeJPEG(width: 80, height: 40, orientation: 1, in: dir)
        try FileManager.default.copyItem(at: wrong, to: dest)
        let image = await ThumbnailService.ensureImageThumbnail(source: source, thumbnailURL: dest, maxEdge: 80)
        let size = pixelSize(image)
        XCTAssertGreaterThan(size.height, size.width)
    }

    func testVideoPreviewCapsResolutionBelow4K() {
        XCTAssertEqual(ThumbnailService.previewMaxResolution.width, ThumbnailService.playerMaxEdge)
        XCTAssertEqual(ThumbnailService.previewMaxResolution.height, ThumbnailService.playerMaxEdge)
        XCTAssertEqual(ThumbnailService.hoverMaxResolution.width, ThumbnailService.storedThumbMaxEdge)
        XCTAssertLessThanOrEqual(ThumbnailService.previewMaxResolution.width, 1280)
    }

    func testPlayerStillMaxEdgeStaysWithinScreenAndHardCap() {
        let edge = ThumbnailService.playerStillMaxEdge(
            for: CGSize(width: 800, height: 500),
            scale: 2
        )
        XCTAssertGreaterThanOrEqual(edge, ThumbnailService.playerMaxEdge)
        XCTAssertLessThanOrEqual(edge, ThumbnailService.playerDisplayMaxEdge)
        let huge = ThumbnailService.playerStillMaxEdge(
            for: CGSize(width: 10_000, height: 10_000),
            scale: 2
        )
        XCTAssertLessThanOrEqual(huge, ThumbnailService.playerDisplayMaxEdge)
    }

    func testDecodeStillNeverKeepsSourceLargerThanMaxEdge() throws {
        let source = try writePNG(width: 2400, height: 1800)
        let image = ThumbnailService.decodeStill(url: source, maxEdge: 96, preferEmbedded: false)
        let size = pixelSize(image)
        XCTAssertNotNil(image)
        XCTAssertLessThanOrEqual(max(size.width, size.height), 96)
    }

    func testPreviewStillDoesNotReplaceGridThumb() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rolltag-preview-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let source = try writePNG(width: 800, height: 600, in: dir)
        let dest = dir.appendingPathComponent("thumb.jpg")
        _ = await ThumbnailService.ensureImageThumbnail(source: source, thumbnailURL: dest, maxEdge: 320)
        let before = try FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int
        _ = await ThumbnailService.previewStill(url: source, maxEdge: 1280)
        let after = try FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int
        XCTAssertEqual(before, after)
    }

    private func writeJPEG(width: Int, height: Int, orientation: Int, in directory: URL? = nil) throws -> URL {
        let dir = directory ?? FileManager.default.temporaryDirectory.appendingPathComponent("rolltag-jpg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("src-\(orientation)-\(UUID().uuidString).jpg")
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw NSError(domain: "ThumbnailTests", code: 2)
        }
        context.setFillColor(CGColor(red: 0.85, green: 0.2, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let cg = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil)
        else {
            throw NSError(domain: "ThumbnailTests", code: 3)
        }
        CGImageDestinationAddImage(
            destination,
            cg,
            [
                kCGImagePropertyOrientation: orientation,
                kCGImageDestinationLossyCompressionQuality: 0.92
            ] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "ThumbnailTests", code: 4)
        }
        return url
    }

    private func writePNG(width: Int, height: Int, in directory: URL? = nil) throws -> URL {
        let dir = directory ?? FileManager.default.temporaryDirectory.appendingPathComponent("rolltag-png-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("src.png")
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.red.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else {
            throw NSError(domain: "ThumbnailTests", code: 1)
        }
        try png.write(to: url)
        return url
    }

    private func pixelSize(_ image: NSImage?) -> NSSize {
        guard let image,
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return .zero }
        return NSSize(width: cg.width, height: cg.height)
    }
}
