import XCTest
@testable import RollTag

final class StockKeywordTests: XCTestCase {
    private let catalog = TagCatalogLoader.load()

    func testChineseCustomTagAddsCatalogFacetAndEnglishStockKeyword() {
        let tags = StockKeywordExpander.expand(
            [TagAssignment.custom("海")!],
            catalog: catalog,
            includeEnglishKeywords: true
        )
        XCTAssertTrue(tags.contains { $0.isCustom && $0.value == "海" })
        XCTAssertTrue(tags.contains { $0.category == "nature" && $0.value == "ocean" })
        XCTAssertTrue(tags.contains { $0.isCustom && $0.value == "ocean" })
    }

    func testStockKeywordsAreLowercasePhrases() {
        XCTAssertEqual(StockKeywordExpander.stockKeyword("Golden Hour"), "golden hour")
        XCTAssertEqual(StockKeywordExpander.stockKeyword("  Ocean  "), "ocean")
        XCTAssertEqual(
            StockKeywordExpander.englishStockKeyword(category: "weather", value: "goldenHour", catalog: catalog),
            "golden hour"
        )
    }

    func testGettyKeywordKeepsEnglishPhrasesOnly() {
        XCTAssertEqual(StockKeywordExpander.gettyKeyword("Icebreaker"), "icebreaker")
        XCTAssertEqual(StockKeywordExpander.gettyKeyword("arctic ocean"), "arctic ocean")
        XCTAssertEqual(StockKeywordExpander.gettyKeyword("close-up"), "close-up")
        XCTAssertNil(StockKeywordExpander.gettyKeyword("ab"))
        XCTAssertNil(StockKeywordExpander.gettyKeyword("破冰船"))
        XCTAssertTrue(StockKeywordExpander.isVisibleCustomLabel("破冰船"))
        XCTAssertFalse(StockKeywordExpander.isVisibleCustomLabel("invented"))
        XCTAssertFalse(StockKeywordExpander.isVisibleCustomLabel("海"))
    }

    func testCountryNameUsesDictionaryNotRomanization() {
        XCTAssertEqual(EnglishKeywordDictionary.englishName(for: "瑞典"), "sweden")
        XCTAssertEqual(EnglishKeywordDictionary.englishName(for: "日本"), "japan")
        let tags = StockKeywordExpander.expand(
            [TagAssignment.custom("瑞典")!],
            catalog: catalog,
            includeEnglishKeywords: true
        )
        XCTAssertTrue(tags.contains { $0.isCustom && $0.value == "瑞典" })
        XCTAssertTrue(tags.contains { $0.isCustom && $0.value == "sweden" })
        XCTAssertFalse(tags.contains { $0.isCustom && $0.value.contains("dian") })
        XCTAssertEqual(StockKeywordExpander.searchAliases(for: "瑞典", catalog: catalog), ["sweden"])
    }

    func testUnmatchedChineseNameGetsRomanizedEnglishKeyword() {
        let tags = StockKeywordExpander.expand(
            [TagAssignment.custom("花花")!],
            catalog: catalog,
            includeEnglishKeywords: true
        )
        XCTAssertTrue(tags.contains { $0.isCustom && $0.value == "花花" })
        let english = tags.first { $0.isCustom && $0.value != "花花" }?.value
        XCTAssertEqual(english, "hua hua")
        XCTAssertFalse(tags.contains { !$0.isCustom })
    }

    func testEnglishCustomDoesNotDuplicate() {
        let tags = StockKeywordExpander.expand(
            [TagAssignment.custom("ocean")!],
            catalog: catalog,
            includeEnglishKeywords: true
        )
        XCTAssertEqual(tags.filter(\.isCustom).map(\.value), ["ocean"])
    }

    func testPresetInChineseModeAlsoWritesEnglishKeyword() {
        let tags = StockKeywordExpander.expand(
            [TagAssignment.user(category: "nature", value: "ocean")],
            catalog: catalog,
            includeEnglishKeywords: true
        )
        XCTAssertTrue(tags.contains { $0.category == "nature" && $0.value == "ocean" })
        XCTAssertTrue(tags.contains { $0.isCustom && $0.value == "ocean" })
    }

    func testSearchAliasesExpandNonEnglishTokens() {
        XCTAssertEqual(StockKeywordExpander.searchAliases(for: "海", catalog: catalog).sorted(), ["ocean"])
        XCTAssertEqual(StockKeywordExpander.searchAliases(for: "花花", catalog: catalog), ["hua hua"])
        XCTAssertTrue(StockKeywordExpander.searchAliases(for: "ocean", catalog: catalog).isEmpty)
    }

    func testEverydayNounsUseDictionaryNotRomanization() {
        XCTAssertGreaterThan(EnglishKeywordDictionary.loadedEntryCount, 50_000)
        let samples: [(String, String)] = [
            ("椅子", "chair"),
            ("桌子", "table"),
            ("房子", "house"),
            ("海洋", "ocean"),
            ("銀河", "milky way"),
            ("星空", "starry sky"),
            ("月亮", "moon"),
            ("樹枝", "branch"),
            ("小溪", "brook"),
            ("漢堡", "hamburger"),
        ]
        for (native, english) in samples {
            XCTAssertEqual(EnglishKeywordDictionary.englishName(for: native), english, native)
            let tags = StockKeywordExpander.expand(
                [TagAssignment.custom(native)!],
                catalog: catalog,
                includeEnglishKeywords: true
            )
            XCTAssertTrue(tags.contains { $0.isCustom && $0.value == native }, native)
            XCTAssertTrue(tags.contains { $0.isCustom && $0.value == english }, native)
            XCTAssertEqual(StockKeywordExpander.searchAliases(for: native, catalog: catalog).first, english, native)
        }
    }

    func testCommonNounUsesDictionaryNotRomanization() {
        XCTAssertEqual(EnglishKeywordDictionary.englishName(for: "破冰船"), "icebreaker")
        XCTAssertEqual(EnglishKeywordDictionary.englishNames(for: "北極破冰船").sorted(), ["arctic", "icebreaker"])
        let tags = StockKeywordExpander.expand(
            [TagAssignment.custom("破冰船")!],
            catalog: catalog,
            includeEnglishKeywords: true
        )
        XCTAssertTrue(tags.contains { $0.isCustom && $0.value == "破冰船" })
        XCTAssertTrue(tags.contains { $0.isCustom && $0.value == "icebreaker" })
        XCTAssertFalse(tags.contains { $0.isCustom && $0.value.contains("bing") })
        XCTAssertEqual(StockKeywordExpander.searchAliases(for: "破冰船", catalog: catalog), ["icebreaker"])
    }

    func testUserGlossaryBeatsRomanizationAndIsBidirectional() {
        let glossary = KeywordGlossary(pairs: [
            KeywordPair(native: "暱稱", english: "Nickname"),
            KeywordPair(native: "品牌", english: "BrandName"),
        ])
        let tags = StockKeywordExpander.expand(
            [TagAssignment.custom("暱稱")!],
            catalog: catalog,
            includeEnglishKeywords: true,
            glossary: glossary
        )
        XCTAssertTrue(tags.contains { $0.isCustom && $0.value == "暱稱" })
        XCTAssertTrue(tags.contains { $0.isCustom && $0.value == "nickname" })
        XCTAssertFalse(tags.contains { $0.isCustom && $0.value.contains("cheng") })

        let reverse = StockKeywordExpander.expand(
            [TagAssignment.custom("Nickname")!],
            catalog: catalog,
            includeEnglishKeywords: false,
            glossary: glossary
        )
        XCTAssertTrue(reverse.contains { $0.isCustom && $0.value == "Nickname" })
        XCTAssertTrue(reverse.contains { $0.isCustom && $0.value == "暱稱" })

        XCTAssertEqual(
            StockKeywordExpander.searchAliases(for: "暱稱", catalog: catalog, glossary: glossary),
            ["nickname"]
        )
        XCTAssertEqual(
            StockKeywordExpander.searchAliases(for: "nickname", catalog: catalog, glossary: glossary),
            ["暱稱"]
        )
        XCTAssertEqual(
            StockKeywordExpander.searchAliases(for: "品牌", catalog: catalog, glossary: glossary),
            ["brandname"]
        )
    }

    func testEnglishModePresetDoesNotAddExtraKeyword() {
        let tags = StockKeywordExpander.expand(
            [TagAssignment.user(category: "nature", value: "ocean")],
            catalog: catalog,
            includeEnglishKeywords: false
        )
        XCTAssertEqual(tags.count, 1)
        XCTAssertEqual(tags.first?.category, "nature")
    }
}
