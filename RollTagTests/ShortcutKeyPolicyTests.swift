import XCTest
@testable import RollTag

final class ShortcutKeyPolicyTests: XCTestCase {
    private let shortcuts = ShortcutPreference.empty

    func testLibraryWindowKeepsGridSelectAllAndPlaybackOnOneScreenAndDualScreen() {
        for dual in [false, true] {
            XCTAssertTrue(
                ShortcutKeyPolicy.allowsLibraryCommands(window: .library, isDualScreen: dual),
                "dual=\(dual)"
            )
            XCTAssertTrue(
                ShortcutKeyPolicy.allowsSelectAll(window: .library, isDualScreen: dual),
                "dual=\(dual)"
            )
            XCTAssertTrue(
                ShortcutKeyPolicy.allowsGridMove(
                    window: .library,
                    isDualScreen: dual,
                    sidebarFocused: false,
                    libraryGridFocused: true,
                    isFullscreen: false,
                    duplicatesActive: false,
                    isDuplicatesCollection: false
                ),
                "dual=\(dual)"
            )
            XCTAssertTrue(
                ShortcutKeyPolicy.allowsStepMedia(window: .library, isFullscreen: false),
                "dual=\(dual)"
            )
            XCTAssertTrue(ShortcutKeyPolicy.allowsPlayback(window: .library), "dual=\(dual)")
            assertDefaultLibraryKeysStillMatch()
        }
    }

    func testDualScreenPlayerWindowUsesTheSameLibraryShortcuts() {
        XCTAssertTrue(ShortcutKeyPolicy.allowsLibraryCommands(window: .playerStage, isDualScreen: true))
        XCTAssertTrue(ShortcutKeyPolicy.allowsSelectAll(window: .playerStage, isDualScreen: true))
        XCTAssertTrue(
            ShortcutKeyPolicy.allowsGridMove(
                window: .playerStage,
                isDualScreen: true,
                sidebarFocused: true,
                libraryGridFocused: false,
                isFullscreen: false,
                duplicatesActive: false,
                isDuplicatesCollection: false
            )
        )
        XCTAssertTrue(ShortcutKeyPolicy.allowsStepMedia(window: .playerStage, isFullscreen: false))
        XCTAssertTrue(ShortcutKeyPolicy.allowsPlayback(window: .playerStage))
        assertDefaultLibraryKeysStillMatch()
    }

    func testPlayerWindowWithoutDualScreenDoesNotStealLibraryKeys() {
        XCTAssertFalse(ShortcutKeyPolicy.allowsLibraryCommands(window: .playerStage, isDualScreen: false))
        XCTAssertFalse(ShortcutKeyPolicy.allowsSelectAll(window: .playerStage, isDualScreen: false))
        XCTAssertFalse(
            ShortcutKeyPolicy.allowsGridMove(
                window: .playerStage,
                isDualScreen: false,
                sidebarFocused: false,
                libraryGridFocused: true,
                isFullscreen: false,
                duplicatesActive: false,
                isDuplicatesCollection: false
            )
        )
        XCTAssertTrue(ShortcutKeyPolicy.allowsStepMedia(window: .playerStage, isFullscreen: false))
        XCTAssertTrue(ShortcutKeyPolicy.allowsPlayback(window: .playerStage))
    }

    func testSidebarOnLibraryWindowBlocksGridUntilTheGridIsFocused() {
        for dual in [false, true] {
            XCTAssertFalse(
                ShortcutKeyPolicy.allowsGridMove(
                    window: .library,
                    isDualScreen: dual,
                    sidebarFocused: true,
                    libraryGridFocused: false,
                    isFullscreen: false,
                    duplicatesActive: false,
                    isDuplicatesCollection: false
                ),
                "dual=\(dual)"
            )
            XCTAssertTrue(
                ShortcutKeyPolicy.allowsGridMove(
                    window: .library,
                    isDualScreen: dual,
                    sidebarFocused: true,
                    libraryGridFocused: true,
                    isFullscreen: false,
                    duplicatesActive: false,
                    isDuplicatesCollection: false
                ),
                "dual=\(dual)"
            )
        }
    }

    func testSettingsTrimAndSheetsNeverMoveTheLibraryGrid() {
        for dual in [false, true] {
            for window: ShortcutKeyWindow in [.settings, .trim, .sheet, .other] {
                XCTAssertFalse(
                    ShortcutKeyPolicy.allowsLibraryCommands(window: window, isDualScreen: dual),
                    "\(window) dual=\(dual)"
                )
                XCTAssertFalse(
                    ShortcutKeyPolicy.allowsGridMove(
                        window: window,
                        isDualScreen: dual,
                        sidebarFocused: false,
                        libraryGridFocused: true,
                        isFullscreen: false,
                        duplicatesActive: false,
                        isDuplicatesCollection: false
                    ),
                    "\(window) dual=\(dual)"
                )
                XCTAssertFalse(
                    ShortcutKeyPolicy.allowsSelectAll(window: window, isDualScreen: dual),
                    "\(window) dual=\(dual)"
                )
                XCTAssertFalse(ShortcutKeyPolicy.allowsPlayback(window: window), "\(window) dual=\(dual)")
                XCTAssertFalse(
                    ShortcutKeyPolicy.allowsStepMedia(window: window, isFullscreen: false),
                    "\(window) dual=\(dual)"
                )
            }
        }
    }

    func testFullscreenAndDuplicatesBlockGridOnBothDisplayModes() {
        for dual in [false, true] {
            XCTAssertFalse(
                ShortcutKeyPolicy.allowsGridMove(
                    window: .library,
                    isDualScreen: dual,
                    sidebarFocused: false,
                    libraryGridFocused: true,
                    isFullscreen: true,
                    duplicatesActive: false,
                    isDuplicatesCollection: false
                )
            )
            XCTAssertFalse(
                ShortcutKeyPolicy.allowsGridMove(
                    window: dual ? .playerStage : .library,
                    isDualScreen: dual,
                    sidebarFocused: false,
                    libraryGridFocused: true,
                    isFullscreen: false,
                    duplicatesActive: true,
                    isDuplicatesCollection: false
                )
            )
            XCTAssertFalse(
                ShortcutKeyPolicy.allowsStepMedia(window: .library, isFullscreen: true)
            )
        }
    }

    private func assertDefaultLibraryKeysStillMatch() {
        XCTAssertEqual(shortcuts.libraryGridDirection(keyCode: ShortcutKeys.leftArrow, modifiers: []), .left)
        XCTAssertEqual(shortcuts.libraryGridDirection(keyCode: ShortcutKeys.rightArrow, modifiers: []), .right)
        XCTAssertEqual(shortcuts.libraryGridDirection(keyCode: ShortcutKeys.upArrow, modifiers: []), .up)
        XCTAssertEqual(shortcuts.libraryGridDirection(keyCode: ShortcutKeys.downArrow, modifiers: []), .down)
        XCTAssertEqual(shortcuts.libraryGridDirection(keyCode: ShortcutKeys.w, modifiers: []), .up)
        XCTAssertEqual(shortcuts.libraryGridDirection(keyCode: ShortcutKeys.a, modifiers: []), .left)
        XCTAssertEqual(shortcuts.libraryGridDirection(keyCode: ShortcutKeys.s, modifiers: []), .down)
        XCTAssertEqual(shortcuts.libraryGridDirection(keyCode: ShortcutKeys.d, modifiers: []), .right)
        XCTAssertTrue(shortcuts.matches(keyCode: ShortcutKeys.space, modifiers: [], .playPause))
        XCTAssertTrue(shortcuts.matches(keyCode: ShortcutKeys.p, modifiers: [], .fullscreen))
        XCTAssertTrue(shortcuts.matches(keyCode: ShortcutKeys.z, modifiers: [], .fitZoom))
        XCTAssertTrue(shortcuts.matches(keyCode: ShortcutKeys.leftBracket, modifiers: [], .previousMedia))
        XCTAssertTrue(shortcuts.matches(keyCode: ShortcutKeys.rightBracket, modifiers: [], .nextMedia))
    }
}
