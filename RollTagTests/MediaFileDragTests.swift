import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import RollTag

final class MediaFileDragTests: XCTestCase {
    func testUnselectedDragExportsOnlyThatID() {
        let dragged = UUID()
        let other = UUID()
        XCTAssertEqual(
            MediaFileDrag.targetIDs(startingAt: dragged, selectedIDs: [other], visibleIDs: [dragged, other]),
            [dragged]
        )
    }

    func testSelectedDragFollowsVisibleOrder() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        XCTAssertEqual(
            MediaFileDrag.targetIDs(
                startingAt: second,
                selectedIDs: [third, first, second],
                visibleIDs: [first, second, third]
            ),
            [first, second, third]
        )
    }

    func testUrlsSkipMissingAndDeduplicatePaths() {
        let first = UUID()
        let missing = UUID()
        let duplicate = UUID()
        let url = URL(fileURLWithPath: "/tmp/clip.mov")
        let urls = MediaFileDrag.urls(ids: [first, missing, duplicate, first]) { id in
            id == missing ? nil : url
        }
        XCTAssertEqual(urls, [url])
    }

    func testExistingFileURLRejectsMissingAndDirectories() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("rolltag-drag-\(UUID().uuidString).mov")
        try Data([0x00]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        XCTAssertEqual(MediaFileDrag.existingFileURL(file), file.standardizedFileURL)
        XCTAssertNil(MediaFileDrag.existingFileURL(file.appendingPathComponent("gone.mov")))
        XCTAssertNil(MediaFileDrag.existingFileURL(FileManager.default.temporaryDirectory))
    }

    func testItemProviderExposesFileURLFilenamesAndText() {
        let url = URL(fileURLWithPath: "/tmp/a.mp4")
        let provider = MediaFileDrag.itemProvider(urls: [url])
        XCTAssertTrue(provider.registeredTypeIdentifiers.contains(UTType.fileURL.identifier))
        XCTAssertTrue(provider.registeredTypeIdentifiers.contains(MediaFileDrag.filenamesType))
        XCTAssertTrue(provider.registeredTypeIdentifiers.contains(UTType.utf8PlainText.identifier))
        XCTAssertTrue(provider.registeredTypeIdentifiers.contains(MediaFileDrag.uriListType))
        XCTAssertEqual(provider.suggestedName, "a.mp4")
    }

    func testEscapedPOSIXPathsEscapeSpacesAndQuotes() {
        let url = URL(fileURLWithPath: "/tmp/my clip's.mov")
        XCTAssertEqual(MediaFileDrag.escapedPOSIXPaths([url]), "/tmp/my\\ clip\\'s.mov")
    }

    func testURIListUsesFileURLs() {
        let first = URL(fileURLWithPath: "/tmp/a.mp4")
        let second = URL(fileURLWithPath: "/tmp/b.jpg")
        XCTAssertEqual(MediaFileDrag.uriList([first, second]), "\(first.absoluteString)\r\n\(second.absoluteString)\r\n")
    }

    func testSharedPasteboardWritesFinderTypes() {
        let pasteboard = NSPasteboard(name: .init("rolltag.drag.test"))
        pasteboard.clearContents()
        let url = URL(fileURLWithPath: "/tmp/photo.jpg")
        MediaFileDrag.writeSharedTypes([url], to: pasteboard)
        XCTAssertEqual(
            pasteboard.propertyList(forType: NSPasteboard.PasteboardType(MediaFileDrag.filenamesType)) as? [String],
            [url.path]
        )
        XCTAssertEqual(pasteboard.string(forType: .string), url.path)
        XCTAssertEqual(pasteboard.string(forType: .fileURL), url.absoluteString)
        XCTAssertEqual(pasteboard.string(forType: NSPasteboard.PasteboardType(MediaFileDrag.uriListType)), "\(url.absoluteString)\r\n")
    }

    func testPasteboardWriterExposesFileURLAndFilenames() {
        let url = URL(fileURLWithPath: "/tmp/clip.wav")
        let writer = MediaFilePasteboardWriter(url: url, allURLs: [url])
        let pasteboard = NSPasteboard(name: .init("rolltag.drag.writer"))
        let types = writer.writableTypes(for: pasteboard)
        XCTAssertTrue(types.contains(.fileURL))
        XCTAssertTrue(types.contains(NSPasteboard.PasteboardType(MediaFileDrag.filenamesType)))
        XCTAssertTrue(types.contains(.string))
        XCTAssertEqual(writer.pasteboardPropertyList(forType: .fileURL) as? String, url.absoluteString)
        XCTAssertEqual(
            writer.pasteboardPropertyList(forType: NSPasteboard.PasteboardType(MediaFileDrag.filenamesType)) as? [String],
            [url.path]
        )
    }

    func testEmptyItemProviderHasNoTypes() {
        let provider = MediaFileDrag.itemProvider(urls: [])
        XCTAssertTrue(provider.registeredTypeIdentifiers.isEmpty)
    }
}
