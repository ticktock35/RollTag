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

    func testMissingFootageRanksWhenTheMissingListPassesItIn() {
        var clip = footage(id: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", name: "sea.mov", tags: [.user(category: "place", value: "ocean")])
        clip.status = .missing
        let ranked = SearchService.rank(
            query: "ocean",
            items: [(clip, .init(warehouseName: "A", warehousePath: "/A", isOnline: true))],
            catalog: catalog,
            locale: "en"
        )
        XCTAssertEqual(ranked.first?.id, clip.id)
    }

    func testCustomTagIsSearchable() {
        let clip = footage(id: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", name: "kid.mov", tags: [.custom("測試")!])
        let ranked = SearchService.rank(
            query: "測試",
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

    func testNonEnglishQueryAlsoMatchesEnglishKeywords() {
        let ocean = footage(id: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", name: "clip.mov", tags: [.user(category: "place", value: "ocean")])
        let englishOnly = footage(id: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB", name: "other.mov", tags: [.custom("ocean")!])
        let romanized = footage(id: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD", name: "kid.mov", tags: [.custom("hua hua")!])
        let bySea = SearchService.rank(
            query: "海",
            items: [
                (ocean, .init(warehouseName: "A", warehousePath: "/A", isOnline: true)),
                (englishOnly, .init(warehouseName: "A", warehousePath: "/A", isOnline: true))
            ],
            catalog: catalog,
            locale: "en"
        )
        XCTAssertEqual(Set(bySea.map(\.id)), [ocean.id, englishOnly.id])
        let byName = SearchService.rank(
            query: "花花",
            items: [(romanized, .init(warehouseName: "A", warehousePath: "/A", isOnline: true))],
            catalog: catalog,
            locale: "en"
        )
        XCTAssertEqual(byName.first?.id, romanized.id)
    }

    func testEnglishQueryIsNotExpandedIntoUnrelatedTokens() {
        XCTAssertEqual(SearchService.expandSearchTokens(["ocean"], catalog: catalog), ["ocean"])
        XCTAssertEqual(SearchService.expandSearchTokens(["海"], catalog: catalog), ["海", "ocean"])
        XCTAssertEqual(SearchService.expandSearchTokens(["瑞典"], catalog: catalog), ["瑞典", "sweden"])
        XCTAssertFalse(SearchService.expandSearchTokens(["瑞典"], catalog: catalog).contains { $0.contains("dian") })
    }

    func testGlossaryQueryMatchesEitherSide() {
        let glossary = KeywordGlossary(pairs: [KeywordPair(native: "暱稱", english: "Nickname")])
        let clip = footage(id: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", name: "kid.mov", tags: [.custom("暱稱")!])
        let byEnglish = SearchService.rank(
            query: "Nickname",
            items: [(clip, .init(warehouseName: "A", warehousePath: "/A", isOnline: true))],
            catalog: catalog,
            locale: "en",
            glossary: glossary
        )
        XCTAssertEqual(byEnglish.first?.id, clip.id)
        XCTAssertEqual(
            SearchService.expandSearchTokens(["nickname"], catalog: catalog, glossary: glossary),
            ["nickname", "暱稱"]
        )
        XCTAssertEqual(
            SearchService.expandSearchTokens(["暱稱"], catalog: catalog, glossary: glossary),
            ["暱稱", "nickname"]
        )
        XCTAssertFalse(
            SearchService.expandSearchTokens(["暱稱"], catalog: catalog, glossary: glossary).contains { $0.contains("cheng") }
        )
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
