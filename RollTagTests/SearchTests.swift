import XCTest
@testable import RollTag

final class SearchTests: XCTestCase {
    private let catalog = TagCatalog(categories: [
        TagCategory(
            id: "mood",
            names: ["zh-Hant": "情緒", "en": "Mood"],
            tags: [TagDefinition(id: "calm", names: ["zh-Hant": "平靜", "en": "Calm"])]
        ),
        TagCategory(
            id: "place",
            names: ["zh-Hant": "地點", "en": "Place"],
            tags: [TagDefinition(id: "ocean", names: ["zh-Hant": "海", "en": "Ocean"])]
        )
    ])

    func testExactTagRanksAboveFilename() {
        let tagged = footage(id: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", name: "clip.mov", tags: [.user(category: "mood", value: "calm")])
        let named = footage(id: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB", name: "calm-broll.mov")
        let ranked = SearchService.rank(
            query: "calm",
            items: [
                (named, .init(warehouseName: "A", warehousePath: "/A", isOnline: true)),
                (tagged, .init(warehouseName: "A", warehousePath: "/A", isOnline: true))
            ],
            catalog: catalog,
            locale: "en"
        )
        XCTAssertEqual(ranked.first?.id, tagged.id)
        XCTAssertGreaterThan(ranked[0].score, ranked[1].score)
    }

    func testOfflineWarehouseIsExcluded() {
        let clip = footage(id: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", name: "sea.mov", tags: [.user(category: "place", value: "ocean")])
        let ranked = SearchService.rank(
            query: "ocean",
            items: [(clip, .init(warehouseName: "Drive", warehousePath: "/Volumes/Off", isOnline: false))],
            catalog: catalog,
            locale: "en"
        )
        XCTAssertTrue(ranked.isEmpty)
    }

    func testMissingFootageIsExcluded() {
        var clip = footage(id: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", name: "sea.mov", tags: [.user(category: "place", value: "ocean")])
        clip.status = .missing
        let ranked = SearchService.rank(
            query: "ocean",
            items: [(clip, .init(warehouseName: "A", warehousePath: "/A", isOnline: true))],
            catalog: catalog,
            locale: "en"
        )
        XCTAssertTrue(ranked.isEmpty)
    }

    func testCustomTagIsSearchable() {
        let clip = footage(id: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", name: "kid.mov", tags: [.custom("皓皓")!])
        let ranked = SearchService.rank(
            query: "皓皓",
            items: [(clip, .init(warehouseName: "A", warehousePath: "/A", isOnline: true))],
            catalog: catalog,
            locale: "zh-Hant"
        )
        XCTAssertEqual(ranked.first?.id, clip.id)
        XCTAssertGreaterThanOrEqual(ranked[0].score, 90)
    }

    func testLocalizedTagAndCategoryMatch() {
        let clip = footage(id: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", name: "x.mov", tags: [.user(category: "mood", value: "calm")])
        let byChinese = SearchService.rank(
            query: "平靜",
            items: [(clip, .init(warehouseName: "A", warehousePath: "/A", isOnline: true))],
            catalog: catalog,
            locale: "zh-Hant"
        )
        let byCategory = SearchService.rank(
            query: "情緒",
            items: [(clip, .init(warehouseName: "A", warehousePath: "/A", isOnline: true))],
            catalog: catalog,
            locale: "zh-Hant"
        )
        XCTAssertEqual(byChinese.first?.id, clip.id)
        XCTAssertEqual(byCategory.first?.id, clip.id)
        XCTAssertGreaterThan(byChinese[0].score, byCategory[0].score)
    }

    func testLibrarySortByFilenameAndSize() {
        let small = footage(id: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", name: "z-last.mov")
        var large = footage(id: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB", name: "a-first.mov")
        large.size = 99
        let items = [
            ScoredFootage(footage: small, score: 1, warehouseName: "A", warehousePath: "/A", isOnline: true),
            ScoredFootage(footage: large, score: 1, warehouseName: "A", warehousePath: "/A", isOnline: true)
        ]
        let byName = SearchService.ordered(items, sort: .filename, ascending: true)
        XCTAssertEqual(byName.map(\.footage.filename), ["a-first.mov", "z-last.mov"])
        let bySize = SearchService.ordered(items, sort: .size, ascending: false)
        XCTAssertEqual(bySize.first?.id, large.id)
    }

    private func footage(id: String, name: String, tags: [TagAssignment] = []) -> Footage {
        Footage(
            id: UUID(uuidString: id)!,
            warehouseID: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            relativePath: name,
            filename: name,
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
