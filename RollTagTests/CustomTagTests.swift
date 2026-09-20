import XCTest
@testable import RollTag

final class CustomTagTests: XCTestCase {
    func testParseSingleCustomName() {
        XCTAssertEqual(TagAssignment.custom("皓皓")?.value, "皓皓")
        XCTAssertEqual(TagAssignment.custom("皓皓")?.category, TagAssignment.customCategory)
        XCTAssertTrue(TagAssignment.custom("皓皓")?.isCustom == true)
    }

    func testParseIgnoresWhitespaceAndEmpty() {
        XCTAssertNil(TagAssignment.custom("   "))
        XCTAssertEqual(TagAssignment.custom("  皓皓  ")?.value, "皓皓")
    }

    func testParseCommaSeparatedCustomTags() {
        let tags = TagAssignment.customs(from: "皓皓，小美, 阿公")
        XCTAssertEqual(tags.map(\.value), ["皓皓", "小美", "阿公"])
        XCTAssertTrue(tags.allSatisfy(\.isCustom))
    }

    func testCustomTagPersistsInWarehouse() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("rolltag-custom-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let db = try WarehouseDatabase(rootURL: root, warehouseID: UUID())
        let snap = FootageSnapshot(
            id: UUID(),
            relativePath: "kid.mov",
            filename: "kid.mov",
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
        try db.addTags([.custom("皓皓")!], to: [snap.id])
        XCTAssertEqual(try db.allFootage()[0].tags.map(\.value), ["皓皓"])
    }

    func testUserAndAISourcesCollapseToOneTag() {
        let tags = [
            TagAssignment.custom("馬來西亞")!,
            TagAssignment(category: TagAssignment.customCategory, value: "馬來西亞", source: "ai"),
            TagAssignment.custom("新山")!,
        ]
        XCTAssertEqual(TagAssignment.uniqued(tags).map(\.value), ["馬來西亞", "新山"])
        XCTAssertEqual(TagAssignment.uniqued(tags).first?.source, "user")
    }

    func testAddingUserTagReplacesAISource() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("rolltag-dup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let db = try WarehouseDatabase(rootURL: root, warehouseID: UUID())
        let snap = FootageSnapshot(
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
        try db.addTags([TagAssignment(category: TagAssignment.customCategory, value: "clubmed", source: "ai")], to: [snap.id])
        try db.addTags([.custom("clubmed")!], to: [snap.id])
        let loaded = try db.allFootage()[0].tags
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.value, "clubmed")
        XCTAssertEqual(loaded.first?.source, "user")
    }
}
