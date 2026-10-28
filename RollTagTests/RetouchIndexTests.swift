import XCTest
@testable import RollTag

final class RetouchIndexTests: XCTestCase {
    private let warehouseID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    func testFindsLookalikeExportWithoutGPS() {
        let pairs = RetouchIndex.resolve(warehouses: [runtime(members: [original(), edited()])], scopes: [])
        XCTAssertEqual(pairs.count, 1)
        XCTAssertEqual(pairs.first?.original.id, original().id)
        XCTAssertEqual(pairs.first?.edited.id, edited().id)
    }

    func testSkipsDeclinedAndAlreadyTaggedAndGPSExport() {
        var tagged = edited(id: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")
        tagged.tags = [TagAssignment.retouch]
        var withGPS = edited(id: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")
        withGPS.latitude = 25
        withGPS.longitude = 121
        withGPS.gpsSource = .header
        let declinedID = edited().id
        let warehouse = runtime(
            members: [original(), edited(), tagged, withGPS],
            declined: [declinedID]
        )
        XCTAssertTrue(RetouchIndex.resolve(warehouses: [warehouse], scopes: []).isEmpty)
    }

    func testFolderScopeKeepsPairIfEditedIsInside() {
        var export = edited()
        export = clip(
            id: export.id.uuidString,
            relativePath: "export/lunch.jpg",
            capturedAt: export.capturedAt,
            phash: export.phash
        )
        let warehouse = runtime(members: [original(), export])
        let inside = FolderRef(warehouseID: warehouseID, relativePath: "export")
        let outside = FolderRef(warehouseID: warehouseID, relativePath: "other")
        XCTAssertEqual(RetouchIndex.resolve(warehouses: [warehouse], scopes: [inside]).count, 1)
        XCTAssertTrue(RetouchIndex.resolve(warehouses: [warehouse], scopes: [outside]).isEmpty)
    }

    func testSidebarCountUsesPendingPairs() {
        let warehouse = runtime(members: [original(), edited()])
        let counts = FootageFilter.collectionCounts(
            warehouses: [warehouse],
            scopes: [],
            duplicateGroups: 0,
            retouchPairs: RetouchIndex.resolve(warehouses: [warehouse], scopes: []).count
        )
        XCTAssertEqual(counts.retouch, 1)
        XCTAssertEqual(counts.value(for: .retouch), 1)
    }

    func testRetouchStoreRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let ids: Set<UUID> = [edited().id]
        try RetouchStore.save(ids, root: root)
        XCTAssertEqual(RetouchStore.load(root: root), ids)
    }

    private func runtime(members: [Footage], declined: Set<UUID> = []) -> WarehouseRuntime {
        WarehouseRuntime(
            preference: WarehousePreference(id: warehouseID, name: "W", path: "/tmp", bookmark: nil),
            isOnline: true,
            isReconciling: false,
            footage: members,
            groups: [],
            declinedRetouchIDs: declined
        )
    }

    private func original() -> Footage {
        var item = clip(id: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", relativePath: "tokyo/IMG_4580.heic", capturedAt: t0)
        item.latitude = 35.6698
        item.longitude = 139.7035
        item.gpsSource = .header
        item.capturedAtHasTimeZone = true
        item.phash = String(repeating: "10", count: 32)
        return item
    }

    private func edited(id: String = "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD") -> Footage {
        clip(
            id: id,
            relativePath: "export/lunch.jpg",
            capturedAt: t0.addingTimeInterval(6 * 3600),
            phash: String(repeating: "10", count: 32)
        )
    }

    private func clip(
        id: String,
        relativePath: String,
        capturedAt: Date?,
        phash: String? = nil
    ) -> Footage {
        Footage(
            id: UUID(uuidString: id)!,
            warehouseID: warehouseID,
            relativePath: relativePath,
            filename: (relativePath as NSString).lastPathComponent,
            size: 1,
            mtime: 1,
            contentHash: "h",
            phash: phash,
            status: .available,
            duration: nil,
            width: 10,
            height: 10,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            parentID: nil,
            userNotes: "",
            tags: [],
            capturedAt: capturedAt
        )
    }
}
