import XCTest
@testable import RollTag

final class ShortcutBindingTests: XCTestCase {
    func testDefaultsMatchCurrentProductKeys() {
        let shortcuts = ShortcutPreference.empty
        XCTAssertEqual(shortcuts.binding(for: .playPause).keyCode, ShortcutKeys.space)
        XCTAssertEqual(shortcuts.binding(for: .fullscreen).keyCode, ShortcutKeys.p)
        XCTAssertEqual(shortcuts.binding(for: .duplicateKeepLeft).keyCode, ShortcutKeys.a)
        XCTAssertEqual(shortcuts.binding(for: .duplicateKeepRight).keyCode, ShortcutKeys.d)
        XCTAssertEqual(shortcuts.binding(for: .duplicateKeepAll).keyCode, ShortcutKeys.s)
        XCTAssertEqual(shortcuts.binding(for: .gridLeft).keyCode, ShortcutKeys.leftArrow)
        XCTAssertEqual(shortcuts.binding(for: .previousMedia).keyCode, ShortcutKeys.leftBracket)
        XCTAssertEqual(shortcuts.binding(for: .nextMedia).keyCode, ShortcutKeys.rightBracket)
    }

    func testOverridePersistsAndResetRestoresDefault() {
        var shortcuts = ShortcutPreference.empty
        shortcuts.set(ShortcutBinding(keyCode: ShortcutKeys.f), for: .fullscreen)
        XCTAssertEqual(shortcuts.binding(for: .fullscreen).keyCode, ShortcutKeys.f)
        XCTAssertEqual(shortcuts.overrides["fullscreen"]?.keyCode, ShortcutKeys.f)
        shortcuts.set(nil, for: .fullscreen)
        XCTAssertEqual(shortcuts.binding(for: .fullscreen).keyCode, ShortcutKeys.p)
        XCTAssertTrue(shortcuts.overrides.isEmpty)
    }

    func testConflictInsideTheSameContext() {
        var shortcuts = ShortcutPreference.empty
        let conflict = shortcuts.conflict(
            assigning: ShortcutBinding(keyCode: ShortcutKeys.space),
            to: .fullscreen
        )
        XCTAssertEqual(conflict, .playPause)
        shortcuts.set(ShortcutBinding(keyCode: ShortcutKeys.f), for: .fullscreen)
        XCTAssertNil(shortcuts.conflict(assigning: ShortcutBinding(keyCode: ShortcutKeys.f), to: .fullscreen))
        XCTAssertEqual(
            shortcuts.conflict(assigning: ShortcutBinding(keyCode: ShortcutKeys.a), to: .playPause),
            .duplicateKeepLeft
        )
    }

    func testShiftDoesNotBlockGridArrows() {
        let binding = ShortcutAction.gridRight.defaultBinding
        XCTAssertTrue(binding.matches(keyCode: ShortcutKeys.rightArrow, modifiers: .shift, allowingShift: true))
        XCTAssertTrue(binding.matches(keyCode: ShortcutKeys.rightArrow, modifiers: [], allowingShift: true))
        XCTAssertFalse(binding.matches(keyCode: ShortcutKeys.rightArrow, modifiers: .shift, allowingShift: false))
    }

    func testReturnMatchesKeypadEnter() {
        let binding = ShortcutAction.confirmAI.defaultBinding
        XCTAssertTrue(binding.matches(keyCode: ShortcutKeys.return, modifiers: []))
        XCTAssertTrue(binding.matches(keyCode: ShortcutKeys.keypadEnter, modifiers: []))
    }

    func testLegacyConfigWithoutShortcutsStillLoads() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("rolltag-pref-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appendingPathComponent("rolltag"), withIntermediateDirectories: true)
        let store = PreferenceStore(homeDirectory: home)
        try Data(#"{"version":1,"warehouses":[]}"#.utf8).write(to: store.configURL)
        let loaded = try store.load()
        XCTAssertEqual(loaded.shortcuts, .empty)
        XCTAssertEqual(loaded.shortcuts.binding(for: .playPause).keyCode, ShortcutKeys.space)
    }

    func testShortcutOverrideRoundTripsInConfig() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("rolltag-pref-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appendingPathComponent("rolltag"), withIntermediateDirectories: true)
        let store = PreferenceStore(homeDirectory: home)
        var file = PreferenceFile.empty
        file.shortcuts.set(ShortcutBinding(keyCode: ShortcutKeys.f), for: .fullscreen)
        try store.save(file)
        let loaded = try store.load()
        XCTAssertEqual(loaded.shortcuts.binding(for: .fullscreen).keyCode, ShortcutKeys.f)
        XCTAssertEqual(loaded.shortcuts.binding(for: .playPause).keyCode, ShortcutKeys.space)
    }

    func testWASDAliasesMoveTheLibraryGrid() {
        let shortcuts = ShortcutPreference.empty
        XCTAssertEqual(shortcuts.libraryGridDirection(keyCode: ShortcutKeys.w, modifiers: []), .up)
        XCTAssertEqual(shortcuts.libraryGridDirection(keyCode: ShortcutKeys.a, modifiers: []), .left)
        XCTAssertEqual(shortcuts.libraryGridDirection(keyCode: ShortcutKeys.s, modifiers: []), .down)
        XCTAssertEqual(shortcuts.libraryGridDirection(keyCode: ShortcutKeys.d, modifiers: []), .right)
        XCTAssertEqual(shortcuts.libraryGridDirection(keyCode: ShortcutKeys.a, modifiers: .shift), .left)
        XCTAssertEqual(shortcuts.libraryGridDirection(keyCode: ShortcutKeys.leftArrow, modifiers: []), .left)
        XCTAssertEqual(shortcuts.libraryGridDirection(keyCode: ShortcutKeys.upArrow, modifiers: []), .up)
    }

    func testWASDAliasYieldsToRemappedGridBinding() {
        var shortcuts = ShortcutPreference.empty
        shortcuts.set(ShortcutBinding(keyCode: ShortcutKeys.a), for: .gridUp)
        XCTAssertEqual(shortcuts.libraryGridDirection(keyCode: ShortcutKeys.a, modifiers: []), .up)
    }

    func testWASDAliasYieldsToOtherLibraryAction() {
        var shortcuts = ShortcutPreference.empty
        shortcuts.set(ShortcutBinding(keyCode: ShortcutKeys.w), for: .fullscreen)
        XCTAssertNil(shortcuts.libraryGridDirection(keyCode: ShortcutKeys.w, modifiers: []))
        XCTAssertEqual(shortcuts.libraryGridDirection(keyCode: ShortcutKeys.a, modifiers: []), .left)
    }

    func testFullscreenStepKeysAndAliases() {
        let shortcuts = ShortcutPreference.empty
        XCTAssertEqual(shortcuts.fullscreenStepDelta(keyCode: ShortcutKeys.leftBracket, modifiers: []), -1)
        XCTAssertEqual(shortcuts.fullscreenStepDelta(keyCode: ShortcutKeys.comma, modifiers: []), -1)
        XCTAssertEqual(shortcuts.fullscreenStepDelta(keyCode: ShortcutKeys.comma, modifiers: .shift), -1)
        XCTAssertEqual(shortcuts.fullscreenStepDelta(keyCode: ShortcutKeys.rightBracket, modifiers: []), 1)
        XCTAssertEqual(shortcuts.fullscreenStepDelta(keyCode: ShortcutKeys.period, modifiers: []), 1)
        XCTAssertEqual(shortcuts.fullscreenStepDelta(keyCode: ShortcutKeys.period, modifiers: .shift), 1)
        XCTAssertNil(shortcuts.fullscreenStepDelta(keyCode: ShortcutKeys.space, modifiers: []))
        XCTAssertEqual(shortcuts.cheatsheetLabel(for: .previousMedia), "[ / ,")
        XCTAssertEqual(shortcuts.cheatsheetLabel(for: .nextMedia), "] / .")
    }

    func testFullscreenStepAliasYieldsToRemap() {
        var shortcuts = ShortcutPreference.empty
        shortcuts.set(ShortcutBinding(keyCode: ShortcutKeys.comma), for: .nextMedia)
        XCTAssertEqual(shortcuts.fullscreenStepDelta(keyCode: ShortcutKeys.comma, modifiers: []), 1)
        XCTAssertEqual(shortcuts.fullscreenStepDelta(keyCode: ShortcutKeys.leftBracket, modifiers: []), -1)
        shortcuts.set(ShortcutBinding(keyCode: ShortcutKeys.period), for: .playPause)
        XCTAssertNil(shortcuts.fullscreenStepDelta(keyCode: ShortcutKeys.period, modifiers: []))
        XCTAssertEqual(shortcuts.fullscreenStepDelta(keyCode: ShortcutKeys.rightBracket, modifiers: []), 1)
    }
}
