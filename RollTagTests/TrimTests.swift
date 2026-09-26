import XCTest
@testable import RollTag

final class TrimTests: XCTestCase {
    func testSanitizedFilenameAddsMp4AndStripsSlashes() {
        XCTAssertEqual(TrimService.sanitizedFilename("  海景/日落  ", fallback: "clip.mp4"), "海景-日落.mp4")
        XCTAssertEqual(TrimService.sanitizedFilename("", fallback: "from_source_cut.mp4"), "from_source_cut.mp4")
        XCTAssertEqual(TrimService.sanitizedFilename("take.mov", fallback: "clip.mp4"), "take.mov")
    }

    func testDefaultFilenameUsesSourceStem() {
        XCTAssertEqual(TrimService.defaultFilename(from: "ice.mov"), "ice_cut.mp4")
    }

    func testRelativePathJoinsFolderAndRejectsDotFolders() {
        XCTAssertEqual(TrimService.relativePath(folder: "malaysia/johor", filename: "cut.mp4"), "malaysia/johor/cut.mp4")
        XCTAssertEqual(TrimService.relativePath(folder: "", filename: "cut.mp4"), "cut.mp4")
        XCTAssertFalse(TrimService.isSafeFolder(".rolltag/trimmed"))
        XCTAssertTrue(TrimService.isSafeFolder("malaysia/johor"))
    }

    func testWarehouseRelativePathStaysInsideRoot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("rolltag-wh-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("desk"), withIntermediateDirectories: true)
        XCTAssertEqual(
            TrimService.warehouseRelativePath(of: root.appendingPathComponent("desk/clip_cut.mp4"), warehouseRoot: root),
            "desk/clip_cut.mp4"
        )
        XCTAssertEqual(
            TrimService.warehouseRelativePath(of: root.appendingPathComponent("clip_cut.mp4"), warehouseRoot: root),
            "clip_cut.mp4"
        )
        XCTAssertNil(TrimService.warehouseRelativePath(of: root, warehouseRoot: root))
        XCTAssertNil(
            TrimService.warehouseRelativePath(
                of: FileManager.default.temporaryDirectory.appendingPathComponent("other.mp4"),
                warehouseRoot: root
            )
        )
        XCTAssertNil(
            TrimService.warehouseRelativePath(of: root.appendingPathComponent(".rolltag/x.mp4"), warehouseRoot: root)
        )
    }

    func testUniqueRelativePathDoesNotOverwrite() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("rolltag-trim-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("desk"), withIntermediateDirectories: true)
        try Data("a".utf8).write(to: root.appendingPathComponent("desk/clip_cut.mp4"))
        let relative = TrimService.uniqueRelativePath(root: root, folder: "desk", filename: "clip_cut.mp4")
        XCTAssertEqual(relative, "desk/clip_cut_2.mp4")
    }

    func testLoopPlayheadStaysInsideInOut() {
        XCTAssertNil(TrimService.loopPlayhead(current: 3.0, start: 2.0, end: 5.0))
        XCTAssertEqual(TrimService.loopPlayhead(current: 5.0, start: 2.0, end: 5.0), 2.0)
        XCTAssertEqual(TrimService.loopPlayhead(current: 1.0, start: 2.0, end: 5.0), 2.0)
    }

    func testReachedOutPoint() {
        XCTAssertFalse(TrimService.reachedOutPoint(current: 4.9, end: 5.0))
        XCTAssertTrue(TrimService.reachedOutPoint(current: 5.0, end: 5.0))
        XCTAssertTrue(TrimService.reachedOutPoint(current: 5.2, end: 5.0))
    }

    func testClampRangeKeepsMinimumDuration() {
        let range = TrimService.clampRange(start: 4.95, end: 5.0, duration: 5.0)
        XCTAssertEqual(range.end - range.start, TrimService.minimumDuration, accuracy: 0.001)
        XCTAssertLessThanOrEqual(range.end, 5.0)
    }

    func testFlattenedFolderPathsSkipRootAndSort() {
        let warehouse = UUID()
        let nodes = WarehouseFolderTree.nodes(
            warehouseID: warehouse,
            from: [
                clip(relativePath: "malaysia/johor/a.mov"),
                clip(id: UUID(), relativePath: "desk/b.mov"),
            ]
        )
        XCTAssertEqual(WarehouseFolderTree.flattenedPaths(from: nodes), ["desk", "malaysia", "malaysia/johor"])
    }

    private func clip(id: UUID = UUID(), relativePath: String) -> Footage {
        Footage(
            id: id,
            warehouseID: UUID(),
            relativePath: relativePath,
            filename: (relativePath as NSString).lastPathComponent,
            size: 10,
            mtime: 1,
            contentHash: nil,
            phash: nil,
            status: .available,
            duration: 1,
            width: 8,
            height: 8,
            createdAt: Date(),
            updatedAt: Date(),
            parentID: nil,
            userNotes: "",
            tags: []
        )
    }
}
