import XCTest
@testable import RollTag

final class PathTagTests: XCTestCase {
    private let catalog = TagCatalog(categories: [
        TagCategory(
            id: "place",
            names: ["zh-Hant": "地點", "en": "Place"],
            tags: [
                TagDefinition(id: "airport", names: ["zh-Hant": "機場", "en": "Airport"]),
                TagDefinition(id: "home", names: ["zh-Hant": "家", "en": "Home"]),
            ]
        ),
        TagCategory(
            id: "mood",
            names: ["zh-Hant": "情緒", "en": "Mood"],
            tags: [TagDefinition(id: "calm", names: ["zh-Hant": "平靜", "en": "Calm"])]
        ),
    ])

    func testLatinSubstringMatchesClubMedFolder() {
        let tags = PathTagMatcher.assignments(
            relativePath: "Travel/馬來西亞/Johor/Club Med Ria/DJI_001.MP4",
            catalog: catalog,
            customValues: ["clubmed", "馬來西亞"]
        )
        XCTAssertTrue(tags.contains { $0.category == "custom" && $0.value == "clubmed" && $0.source == "path" })
        XCTAssertTrue(tags.contains { $0.category == "custom" && $0.value == "馬來西亞" && $0.source == "path" })
    }

    func testHanRequiresWholeFolderSegment() {
        let tags = PathTagMatcher.assignments(
            relativePath: "Travel/馬來西亞/clip.mp4",
            catalog: catalog,
            customValues: ["馬"]
        )
        XCTAssertFalse(tags.contains { $0.value == "馬" })
    }

    func testPlaceEnglishNameAndIdMatch() {
        let tags = PathTagMatcher.assignments(
            relativePath: "Airport/terminal.mp4",
            catalog: catalog,
            customValues: []
        )
        XCTAssertEqual(tags.map(\.identityKey), ["place/airport"])
        XCTAssertEqual(tags.first?.source, "path")
    }

    func testMoodTagsAreNotAppliedFromPath() {
        let tags = PathTagMatcher.assignments(
            relativePath: "Calm/clip.mp4",
            catalog: catalog,
            customValues: []
        )
        XCTAssertTrue(tags.isEmpty)
    }

    func testFilenameIsNotAFolderSegment() {
        let tags = PathTagMatcher.assignments(
            relativePath: "DJI_20260919143022_0029_D.MP4",
            catalog: catalog,
            customValues: ["clubmed"]
        )
        XCTAssertTrue(tags.isEmpty)
    }

    func testUserOutranksPathOutranksAI() {
        let tags = TagAssignment.uniqued([
            .ai(category: "custom", value: "clubmed"),
            .path(category: "custom", value: "clubmed"),
            .user(category: "custom", value: "clubmed"),
        ])
        XCTAssertEqual(tags.map(\.source), ["user"])
    }

    func testAudioCannotAITagAndTinyVideoCannot() {
        var audio = clip(filename: "guide.mp3")
        XCTAssertFalse(audio.canAITag)
        var photo = clip(filename: "shot.heic")
        photo.size = 20_000
        XCTAssertTrue(photo.canAITag)
        var tiny = clip(filename: "DJI_0029_D.MP4")
        tiny.size = 1024
        XCTAssertFalse(tiny.canAITag)
        var video = tiny
        video.size = 12_000_000
        XCTAssertTrue(video.canAITag)
        video.tags = [.ai(category: "mood", value: "calm"), .user(category: "custom", value: "clubmed")]
        XCTAssertTrue(video.canAITag)
    }

    private func clip(filename: String) -> Footage {
        Footage(
            id: UUID(),
            warehouseID: UUID(),
            relativePath: filename,
            filename: filename,
            size: 1,
            mtime: 1,
            contentHash: "h",
            phash: nil,
            status: .available,
            duration: 1,
            width: 10,
            height: 10,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            parentID: nil,
            userNotes: "",
            tags: [],
            capturedAt: nil
        )
    }
}
