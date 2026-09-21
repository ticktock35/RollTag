import XCTest
@testable import RollTag

final class ShortcutKeysTests: XCTestCase {
    func testLatinLettersComeFromPhysicalKeyCodes() {
        XCTAssertEqual(ShortcutKeys.latinLetter(keyCode: ShortcutKeys.a), "a")
        XCTAssertEqual(ShortcutKeys.latinLetter(keyCode: ShortcutKeys.s), "s")
        XCTAssertEqual(ShortcutKeys.latinLetter(keyCode: ShortcutKeys.d), "d")
        XCTAssertEqual(ShortcutKeys.latinLetter(keyCode: ShortcutKeys.p), "p")
        XCTAssertEqual(ShortcutKeys.latinLetter(keyCode: ShortcutKeys.space), " ")
        XCTAssertNil(ShortcutKeys.latinLetter(keyCode: ShortcutKeys.escape))
        XCTAssertEqual(ShortcutKeys.arrowDirection(keyCode: ShortcutKeys.leftArrow), .left)
        XCTAssertEqual(ShortcutKeys.arrowDirection(keyCode: ShortcutKeys.rightArrow), .right)
        XCTAssertEqual(ShortcutKeys.arrowDirection(keyCode: ShortcutKeys.upArrow), .up)
        XCTAssertEqual(ShortcutKeys.arrowDirection(keyCode: ShortcutKeys.downArrow), .down)
        XCTAssertNil(ShortcutKeys.arrowDirection(keyCode: ShortcutKeys.escape))
        XCTAssertEqual(ShortcutKeys.wasdDirection(keyCode: ShortcutKeys.w), .up)
        XCTAssertEqual(ShortcutKeys.wasdDirection(keyCode: ShortcutKeys.a), .left)
        XCTAssertEqual(ShortcutKeys.wasdDirection(keyCode: ShortcutKeys.s), .down)
        XCTAssertEqual(ShortcutKeys.wasdDirection(keyCode: ShortcutKeys.d), .right)
        XCTAssertNil(ShortcutKeys.wasdDirection(keyCode: ShortcutKeys.p))
        XCTAssertEqual(ShortcutKeys.displayName(keyCode: ShortcutKeys.leftBracket), "[")
        XCTAssertEqual(ShortcutKeys.displayName(keyCode: ShortcutKeys.rightBracket), "]")
        XCTAssertEqual(ShortcutKeys.displayName(keyCode: ShortcutKeys.comma), ",")
        XCTAssertEqual(ShortcutKeys.displayName(keyCode: ShortcutKeys.period), ".")
    }

    func testBopomofoAndCJKCountAsIMECharacters() {
        XCTAssertTrue(ShortcutKeys.looksLikeIMECharacter("ㄅ"))
        XCTAssertTrue(ShortcutKeys.looksLikeIMECharacter("あ"))
        XCTAssertTrue(ShortcutKeys.looksLikeIMECharacter("啊"))
        XCTAssertFalse(ShortcutKeys.looksLikeIMECharacter("a"))
        XCTAssertFalse(ShortcutKeys.looksLikeIMECharacter("P"))
        XCTAssertFalse(ShortcutKeys.looksLikeIMECharacter(" "))
        XCTAssertFalse(ShortcutKeys.looksLikeIMECharacter(nil))
    }

    func testHintWhenCharactersAreNotLatinEvenIfSourceUnknown() {
        XCTAssertTrue(ShortcutKeys.shouldHintSwitchInputSource(characters: "ㄉ", keyCode: ShortcutKeys.d))
        XCTAssertFalse(ShortcutKeys.shouldHintSwitchInputSource(characters: "d", keyCode: 999))
    }
}
