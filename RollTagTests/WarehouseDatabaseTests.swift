import XCTest
@testable import RollTag

final class WarehouseDatabaseTests: XCTestCase {
    func testRelativePathsAndReservedColumnsRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("rolltag-db-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let warehouseID = UUID()
        let db = try WarehouseDatabase(rootURL: root, warehouseID: warehouseID)

        var snap = FootageSnapshot(
            id: UUID(),
            relativePath: "japan/street.mov",
            filename: "street.mov",
            size: 12,
            mtime: 99,
            contentHash: "hash-1",
            phash: "1010",
            status: .available,
            tags: [.user(category: "place", value: "street")],
            userNotes: "night market",
            parentID: nil,
            duration: 4.5,
            width: 1920,
            height: 1080,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            needsReanalysis: false
        )
        try db.insert(snap)
        let loaded = try db.allFootage()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].relativePath, "japan/street.mov")
        XCTAssertEqual(loaded[0].warehouseID, warehouseID)
        XCTAssertEqual(loaded[0].tags.first?.value, "street")
        XCTAssertEqual(loaded[0].userNotes, "night market")

        snap.relativePath = "japan/renamed.mov"
        snap.filename = "renamed.mov"
        try db.update(snap)
        XCTAssertEqual(try db.allFootage()[0].relativePath, "japan/renamed.mov")

        XCTAssertTrue(FileManager.default.fileExists(atPath: db.databaseURL.path))
        XCTAssertTrue(db.databaseURL.path.contains("/.rolltag/warehouse.sqlite"))
    }

    func testRemovingTagClearsAnySource() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("rolltag-db-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let db = try WarehouseDatabase(rootURL: root, warehouseID: UUID())
        var snap = FootageSnapshot(
            id: UUID(),
            relativePath: "a.mov",
            filename: "a.mov",
            size: 1,
            mtime: 1,
            contentHash: "h",
            phash: nil,
            status: .available,
            tags: [],
            userNotes: "",
            parentID: nil,
            duration: nil,
            width: nil,
            height: nil,
            capturedAt: nil,
            needsReanalysis: false
        )
        try db.insert(snap)
        try db.addTags([.ai(category: "nature", value: "ocean")], to: [snap.id])
        XCTAssertEqual(try db.allFootage()[0].tags.first?.source, "ai")
        try db.removeTags([.user(category: "nature", value: "ocean")], from: [snap.id])
        XCTAssertTrue(try db.allFootage()[0].tags.isEmpty)
    }

    func testRemoveFootageDeletesRow() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("rolltag-db-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let db = try WarehouseDatabase(rootURL: root, warehouseID: UUID())
        let snap = FootageSnapshot(
            id: UUID(),
            relativePath: "gone.mov",
            filename: "gone.mov",
            size: 1,
            mtime: 1,
            contentHash: "h",
            phash: nil,
            status: .available,
            tags: [.user(category: "place", value: "street")],
            userNotes: "",
            parentID: nil,
            duration: nil,
            width: nil,
            height: nil,
            capturedAt: nil,
            needsReanalysis: false
        )
        try db.insert(snap)
        XCTAssertEqual(try db.allFootage().count, 1)
        try db.removeFootage(id: snap.id)
        XCTAssertTrue(try db.allFootage().isEmpty)
    }
}
