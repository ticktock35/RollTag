import XCTest
@testable import RollTag

final class CustomTagTests: XCTestCase {
    func testParseSingleCustomName() {
        XCTAssertEqual(TagAssignment.custom("測試")?.value, "測試")
        XCTAssertEqual(TagAssignment.custom("測試")?.category, TagAssignment.customCategory)
        XCTAssertTrue(TagAssignment.custom("測試")?.isCustom == true)
    }

    func testParseIgnoresWhitespaceAndEmpty() {
        XCTAssertNil(TagAssignment.custom("   "))
        XCTAssertEqual(TagAssignment.custom("  測試  ")?.value, "測試")
    }

    func testParseCommaSeparatedCustomTags() {
        let tags = TagAssignment.customs(from: "測試，小美, 阿公")
        XCTAssertEqual(tags.map(\.value), ["測試", "小美", "阿公"])
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
        try db.addTags([.custom("測試")!], to: [snap.id])
        XCTAssertEqual(try db.allFootage()[0].tags.map(\.value), ["測試"])
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

    func testPathLosesToUserButBeatsAI() {
        let tags = [
            TagAssignment(category: TagAssignment.customCategory, value: "clubmed", source: "ai"),
            TagAssignment.path(category: TagAssignment.customCategory, value: "clubmed"),
        ]
        XCTAssertEqual(TagAssignment.uniqued(tags).first?.source, "path")
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

    func testRememberRecentMovesUsedToFrontAndCaps() {
        let recent = TagAssignment.rememberRecent(["舊的", "更舊"], used: ["新的", "舊的"])
        XCTAssertEqual(recent, ["舊的", "新的", "更舊"])
        let many = (1...60).map { "標\($0)" }
        let capped = TagAssignment.rememberRecent([], used: many)
        XCTAssertEqual(capped.count, TagAssignment.recentUsedLimit)
        XCTAssertEqual(capped.first, "標60")
        XCTAssertEqual(capped.last, "標11")
    }

    func testRecentUsedShowsNewestFirstAndCapsAt50() {
        let tags = (1...60).map { TagAssignment.custom("標\($0)")! }
        let unused = TagAssignment.recentUsed(tags, recentValues: [])
        XCTAssertEqual(unused.count, 50)
        XCTAssertEqual(unused.first?.value, "標1")
        let recent = TagAssignment.recentUsed(tags, recentValues: ["標60", "標3"])
        XCTAssertEqual(recent.count, 50)
        XCTAssertEqual(recent.map(\.value).prefix(3), ["標60", "標3", "標1"])
        XCTAssertFalse(recent.contains { $0.value == "標59" })
    }
}
