import AppKit
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
