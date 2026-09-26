import XCTest
@testable import RollTag

final class PreferenceTests: XCTestCase {
    func testAddEditRemoveDoNotTouchDiskFiles() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("rolltag-pref-\(UUID().uuidString)")
        let warehouse = FileManager.default.temporaryDirectory.appendingPathComponent("rolltag-wh-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: warehouse, withIntermediateDirectories: true)
        let clip = warehouse.appendingPathComponent("keep.mov")
        try Data("video".utf8).write(to: clip)

        let store = PreferenceStore(homeDirectory: home)
        var file = PreferenceFile.empty
        file = store.addWarehouse(named: "Travel", path: warehouse.path, to: file)
        XCTAssertEqual(file.warehouses.count, 1)
        XCTAssertTrue(store.isOnline(file.warehouses[0]))

        let id = file.warehouses[0].id
        file = store.updateWarehouse(id: id, name: "Travel 2024", path: nil, in: file)
        XCTAssertEqual(file.warehouses[0].name, "Travel 2024")

        try store.save(file)
        let loaded = try store.load()
        XCTAssertEqual(loaded.warehouses.first?.name, "Travel 2024")
        XCTAssertEqual(loaded.warehouses.first?.path, warehouse.path)

        file = store.removeWarehouse(id: id, from: file)
        XCTAssertTrue(file.warehouses.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: clip.path))
    }

    func testOfflineWarehouseStaysInPreference() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("rolltag-pref-\(UUID().uuidString)")
        let store = PreferenceStore(homeDirectory: home)
        var file = store.addWarehouse(named: "Missing Disk", path: "/Volumes/DoesNotExistRollTag", to: PreferenceFile.empty)
        XCTAssertFalse(store.isOnline(file.warehouses[0]))
        try store.save(file)
        file = try store.load()
        XCTAssertEqual(file.warehouses.count, 1)
        XCTAssertEqual(file.warehouses[0].name, "Missing Disk")
    }

    func testAIKeysRoundTripAndOldConfigStillLoads() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("rolltag-pref-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appendingPathComponent("rolltag"), withIntermediateDirectories: true)
        let store = PreferenceStore(homeDirectory: home)
        var file = PreferenceFile.empty
        file = store.updateAI(selectedProvider: .gemini, in: file)
        file = store.updateAIKey(provider: .gemini, apiKey: "gem-test", model: "gemini-2.5-flash", in: file)
        try store.save(file)
        let loaded = try store.load()
        XCTAssertEqual(loaded.ai.selectedProvider, .gemini)
        XCTAssertEqual(loaded.ai.settings(for: .gemini).apiKey, "gem-test")
        XCTAssertTrue(loaded.ai.hasKey(for: .gemini))
        XCTAssertFalse(loaded.ai.hasKey(for: .openai))

        let legacy = """
        {"version":1,"warehouses":[]}
        """
        try Data(legacy.utf8).write(to: store.configURL)
        let migrated = try store.load()
        XCTAssertEqual(migrated.ai, .empty)
    }

    func testGlossaryRoundTripAndLegacyConfigStaysEmpty() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("rolltag-pref-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appendingPathComponent("rolltag"), withIntermediateDirectories: true)
        let store = PreferenceStore(homeDirectory: home)
        var file = PreferenceFile.empty
        file.glossary = file.glossary.adding(native: "暱稱", english: "Nickname")!
        file.glossary = file.glossary.adding(native: "品牌", english: "BrandName")!
        try store.save(file)
        let loaded = try store.load()
        XCTAssertEqual(loaded.glossary.pairs.map(\.native), ["暱稱", "品牌"])
        XCTAssertEqual(loaded.glossary.pairs.map(\.english), ["Nickname", "BrandName"])
        XCTAssertEqual(loaded.glossary.counterparts(for: "暱稱"), ["nickname"])
        XCTAssertEqual(loaded.glossary.counterparts(for: "Nickname"), ["暱稱"])
        file.glossary = loaded.glossary.adding(native: "暱稱", english: "Nickname Two")!
        XCTAssertEqual(file.glossary.pairs.count, 2)
        XCTAssertEqual(file.glossary.counterparts(for: "暱稱"), ["nickname two"])
        XCTAssertEqual(file.glossary.counterparts(for: "品牌"), ["brandname"])

        let legacy = """
        {"version":1,"warehouses":[]}
        """
        try Data(legacy.utf8).write(to: store.configURL)
        let migrated = try store.load()
        XCTAssertEqual(migrated.glossary, .empty)
    }

    func testAITaggingExamplesRoundTrip() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("rolltag-pref-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appendingPathComponent("rolltag"), withIntermediateDirectories: true)
        let store = PreferenceStore(homeDirectory: home)
        var file = PreferenceFile.empty
        file.ai.examples = [
            AITaggingExample(
                ai: [AITagRef(category: "nature", value: "ocean")],
                kept: [AITagRef(category: "nature", value: "lake")]
            )
        ]
        try store.save(file)
        let loaded = try store.load()
        XCTAssertEqual(loaded.ai.examples.first?.ai.first?.value, "ocean")
        XCTAssertEqual(loaded.ai.examples.first?.kept.first?.value, "lake")
    }

    func testRecentCustomTagsRoundTripAndLegacyStaysEmpty() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("rolltag-pref-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appendingPathComponent("rolltag"), withIntermediateDirectories: true)
        let store = PreferenceStore(homeDirectory: home)
        var file = PreferenceFile.empty
        file.recentCustomTags = ["小美", "clubmed"]
        try store.save(file)
        let loaded = try store.load()
        XCTAssertEqual(loaded.recentCustomTags, ["小美", "clubmed"])

        let legacy = """
        {"version":1,"warehouses":[]}
        """
        try Data(legacy.utf8).write(to: store.configURL)
        let migrated = try store.load()
        XCTAssertTrue(migrated.recentCustomTags.isEmpty)
    }

    func testDuplicatePathIsNotAddedTwice() {
        let store = PreferenceStore(homeDirectory: FileManager.default.temporaryDirectory)
        var file = store.addWarehouse(named: "A", path: "/tmp/wh", to: .empty)
        file = store.addWarehouse(named: "B", path: "/tmp/wh", to: file)
        XCTAssertEqual(file.warehouses.count, 1)
    }
}
