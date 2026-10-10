import XCTest
@testable import RollTag

final class UserGuideTests: XCTestCase {
    func testGuideFilesExposeRequiredTopics() throws {
        let resources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("RollTag/Resources")
        for name in ["UserGuide.zh-Hant.md", "UserGuide.en.md"] {
            let text = try String(contentsOf: resources.appendingPathComponent(name), encoding: .utf8)
            XCTAssertEqual(
                UserGuide.parse(text).map(\.id),
                UserGuide.expectedIDs,
                name
            )
        }
    }

    func testAppBundleContainsGuides() {
        let bundle = Bundle(for: AppModel.self)
        XCTAssertNotNil(bundle.url(forResource: "UserGuide.en", withExtension: "md"))
        XCTAssertNotNil(bundle.url(forResource: "UserGuide.zh-Hant", withExtension: "md"))
        XCTAssertEqual(
            UserGuide.topics(localeID: "zh-Hant").map(\.id),
            UserGuide.expectedIDs
        )
        XCTAssertEqual(
            UserGuide.topics(localeID: "en").map(\.id),
            UserGuide.expectedIDs
        )
    }

    func testParseIgnoresDocumentTitleAndKeepsBody() {
        let markdown = """
        # Guide
        ## Start {#start}
        First paragraph.

        Second line.
        ## Next {#next}
        Other.
        """
        let topics = UserGuide.parse(markdown)
        XCTAssertEqual(topics.map(\.id), ["start", "next"])
        XCTAssertEqual(topics[0].title, "Start")
        XCTAssertTrue(topics[0].body.contains("First paragraph."))
        XCTAssertTrue(topics[0].body.contains("Second line."))
        XCTAssertEqual(topics[1].title, "Next")
    }

    func testBlocksKeepListsOnSeparateLines() {
        let body = """
        常用預設（可在設定 → 快捷鍵改；⌘/ 看完整列表）：

        - **空白鍵**：播放／暫停
        - **P**：全螢幕（再按一次或 Esc 離開）
        - **⌘/**：快捷鍵一覽

        說明選單或檢視選單也可打開快捷鍵一覽。
        """
        XCTAssertEqual(
            UserGuide.blocks(in: body),
            [
                .paragraph("常用預設（可在設定 → 快捷鍵改；⌘/ 看完整列表）："),
                .bullets([
                    "**空白鍵**：播放／暫停",
                    "**P**：全螢幕（再按一次或 Esc 離開）",
                    "**⌘/**：快捷鍵一覽",
                ]),
                .paragraph("說明選單或檢視選單也可打開快捷鍵一覽。"),
            ]
        )
    }

    func testBlocksParseNumberedSteps() {
        let body = """
        第一次建議這樣走：

        1. 拖一個資料夾進來。
        2. 點格子看圖。
        """
        XCTAssertEqual(
            UserGuide.blocks(in: body),
            [
                .paragraph("第一次建議這樣走："),
                .steps(["拖一個資料夾進來。", "點格子看圖。"]),
            ]
        )
    }
}
