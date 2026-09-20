import XCTest
@testable import RollTag

final class TagCatalogTests: XCTestCase {
    func testEnglishAppLanguageShowsEnglishPresetNames() {
        XCTAssertEqual(TagCatalogLoader.mapped("en"), "en")
        XCTAssertEqual(TagCatalogLoader.mapped("en-US"), "en")
        XCTAssertEqual(TagCatalogLoader.mapped("en_GB"), "en")
        XCTAssertEqual(TagCatalogLoader.localeID(from: Locale(identifier: "en_US")), "en")
        XCTAssertEqual(TagCatalogLoader.localeID(preferred: ["en"]), "en")

        let catalog = TagCatalogLoader.load()
        let nature = catalog.categories.first { $0.id == "nature" }
        XCTAssertEqual(nature?.localizedName(locale: "en"), "Nature")
        XCTAssertEqual(nature?.tags.first { $0.id == "ocean" }?.localizedName(locale: "en"), "Ocean")
        XCTAssertEqual(nature?.localizedName(locale: "zh-Hant"), "自然")
        XCTAssertEqual(nature?.tags.first { $0.id == "ocean" }?.localizedName(locale: "zh-Hant"), "海")
    }

    func testTraditionalChineseLocalesStayChinese() {
        XCTAssertEqual(TagCatalogLoader.mapped("zh-Hant"), "zh-Hant")
        XCTAssertEqual(TagCatalogLoader.mapped("zh-TW"), "zh-Hant")
        XCTAssertEqual(TagCatalogLoader.mapped("zh_TW"), "zh-Hant")
        XCTAssertEqual(TagCatalogLoader.localeID(from: Locale(identifier: "zh_TW")), "zh-Hant")
        XCTAssertEqual(TagCatalogLoader.localeID(preferred: ["zh-Hant", "en"]), "zh-Hant")
    }

    func testEveryPresetTagHasEnglishAndChineseNames() throws {
        let catalog = TagCatalogLoader.load()
        XCTAssertFalse(catalog.categories.isEmpty)
        for category in catalog.categories {
            XCTAssertFalse(category.names["en", default: ""].isEmpty, category.id)
            XCTAssertFalse(category.names["zh-Hant", default: ""].isEmpty, category.id)
            XCTAssertFalse(category.names["en", default: ""].unicodeScalars.contains { $0.value >= 0x4E00 && $0.value <= 0x9FFF }, category.id)
            for tag in category.tags {
                XCTAssertFalse(tag.names["en", default: ""].isEmpty, "\(category.id)/\(tag.id)")
                XCTAssertFalse(tag.names["zh-Hant", default: ""].isEmpty, "\(category.id)/\(tag.id)")
                XCTAssertFalse(
                    tag.names["en", default: ""].unicodeScalars.contains { $0.value >= 0x4E00 && $0.value <= 0x9FFF },
                    "\(category.id)/\(tag.id) English name is not English"
                )
            }
        }
    }
}
