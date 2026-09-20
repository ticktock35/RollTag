import XCTest
@testable import RollTag

final class FootageFilterTests: XCTestCase {
    private let catalog = TagCatalog(categories: [
        TagCategory(id: "mood", names: ["zh-Hant": "情緒", "en": "Mood"], tags: []),
        TagCategory(id: "nature", names: ["zh-Hant": "自然", "en": "Nature"], tags: [])
    ])

    func testTaggedCollectionOnlyShowsTaggedAvailableFootage() {
        let tagged = clip(tags: [.user(category: "mood", value: "calm")])
        let bare = clip(id: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB", tags: [])
        XCTAssertTrue(FootageFilter.include(footage: tagged, isOnline: true, selection: .collection(.tagged), isDuplicate: false))
        XCTAssertFalse(FootageFilter.include(footage: bare, isOnline: true, selection: .collection(.tagged), isDuplicate: false))
        XCTAssertTrue(FootageFilter.include(footage: bare, isOnline: true, selection: .collection(.untagged), isDuplicate: false))
    }

    func testExistingTagsAppearUnderTheirCategory() {
        let mood = clip(tags: [.user(category: "mood", value: "calm")])
        let custom = clip(id: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB", tags: [.custom("皓皓")!])
        XCTAssertTrue(FootageFilter.include(footage: mood, isOnline: true, selection: .tagCategory("mood"), isDuplicate: false))
        XCTAssertFalse(FootageFilter.include(footage: custom, isOnline: true, selection: .tagCategory("mood"), isDuplicate: false))
        XCTAssertTrue(FootageFilter.include(footage: custom, isOnline: true, selection: .tagCategory(TagAssignment.customCategory), isDuplicate: false))
    }

    func testPopulatedCategoriesIncludeUsedPresetAndCustom() {
        let footage = [
            clip(tags: [.user(category: "mood", value: "calm")]),
            clip(id: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB", tags: [.custom("皓皓")!])
        ]
        let categories = FootageFilter.populatedCategories(
            from: footage,
            catalog: catalog,
            locale: "zh-Hant",
            customTitle: "自訂"
        )
        XCTAssertEqual(categories.map(\.id), ["mood", "custom"])
        XCTAssertEqual(categories.first?.title, "情緒")
        XCTAssertEqual(categories.last?.title, "自訂")
    }

    func testUnusedCategoryDoesNotAppear() {
        let footage = [clip(tags: [.user(category: "mood", value: "calm")])]
        let categories = FootageFilter.populatedCategories(
            from: footage,
            catalog: catalog,
            locale: "en",
            customTitle: "Custom"
        )
        XCTAssertEqual(categories.map(\.id), ["mood"])
    }

    func testTinyVideoIsTooSmallToPreview() {
        var tiny = clip(tags: [])
        tiny.size = 1024
        tiny.filename = "DJI_0029_D.MP4"
        tiny.relativePath = "DJI_0029_D.MP4"
        XCTAssertTrue(tiny.isTooSmallToPreview)

        var real = tiny
        real.size = 12_000_000
        XCTAssertFalse(real.isTooSmallToPreview)
    }

    private func clip(id: String = "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", tags: [TagAssignment]) -> Footage {
        Footage(
            id: UUID(uuidString: id)!,
            warehouseID: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            relativePath: "clip.mov",
            filename: "clip.mov",
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
            tags: tags,
            capturedAt: nil
        )
    }
}
