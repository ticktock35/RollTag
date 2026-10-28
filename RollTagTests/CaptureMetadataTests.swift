import XCTest
@testable import RollTag

final class CaptureMetadataTests: XCTestCase {
    func testDJIFilenameParsesNaiveCameraClock() {
        let clock = MediaMetadata.parseDJIFilename("DJI_20260919143022_0029_D.MP4")
        XCTAssertEqual(clock?.local, "2026-09-19T14:30:22")
        XCTAssertEqual(clock?.hasTimeZone, false)
        XCTAssertEqual(clock?.year, 2026)
        XCTAssertNotNil(clock?.date)
        XCTAssertNil(MediaMetadata.parseDJIFilename("clip_20260919143022.mp4"))
        XCTAssertNil(MediaMetadata.parseDJIFilename("DJI_0029_D.MP4"))
    }

    func testImplausibleYear2000IsRejected() {
        let bad = MediaMetadata.CaptureClock(
            date: Date(timeIntervalSince1970: 946_684_800),
            local: "2000-01-01T00:00:00",
            hasTimeZone: false,
            year: 2000
        )
        XCTAssertFalse(MediaMetadata.isPlausible(bad))

        let ok = MediaMetadata.parseDJIFilename("DJI_20260919143022_0029_D.MP4")!
        XCTAssertTrue(MediaMetadata.isPlausible(ok))
    }

    func testEXIFWithoutOffsetStaysNaive() {
        let clock = MediaMetadata.parseEXIFClock("2024:03:01 09:08:07", offset: nil)
        XCTAssertEqual(clock?.local, "2024-03-01T09:08:07")
        XCTAssertEqual(clock?.hasTimeZone, false)
        XCTAssertEqual(clock?.year, 2024)
    }

    func testEXIFWithOffsetHasTimeZone() {
        let clock = MediaMetadata.parseEXIFClock("2024:03:01 09:08:07", offset: "+08:00")
        XCTAssertEqual(clock?.hasTimeZone, true)
        XCTAssertNotNil(clock?.date)
    }

    func testNaiveClockSentToAIWithoutZ() {
        var footage = sampleFootage()
        footage.capturedAtLocal = "2026-09-19T14:30:22"
        footage.capturedAtHasTimeZone = false
        footage.capturedAtSource = .djiFilename
        let payload = AITagSuggester.contextPayload(footage: footage, warehouseName: "Travel")
        XCTAssertEqual(payload["captured_at"] as? String, "2026-09-19T14:30:22")
        XCTAssertFalse((payload["captured_at"] as? String ?? "").contains("Z"))
    }

    func testZeroZeroGPSIsTreatedAsMissing() {
        var snapshot = MediaMetadataSnapshot(latitude: 0, longitude: 0, altitude: 0, gpsSource: .header)
        XCTAssertFalse(snapshot.hasGPS)
        XCTAssertTrue(snapshot.shouldResetMisplacedGPS)
        snapshot = snapshot.sanitized()
        XCTAssertNil(snapshot.latitude)
        XCTAssertNil(snapshot.longitude)
        XCTAssertNil(snapshot.gpsSource)
        XCTAssertTrue(MediaMetadata.isUsableGPS(latitude: 35.6699, longitude: 139.7048))
        XCTAssertFalse(MediaMetadata.isUsableGPS(latitude: 0, longitude: 0))
        XCTAssertNil(MediaMetadata.parseISO6709("+0.0+0.0+0.0/"))
    }

    func testItineraryGuessedGPSIsMarkedForReset() {
        let guessed = MediaMetadataSnapshot(latitude: 42.775, longitude: 141.692, gpsSource: .itinerary)
        XCTAssertTrue(guessed.hasGPS)
        XCTAssertTrue(guessed.shouldResetMisplacedGPS)
        let header = MediaMetadataSnapshot(latitude: 35.6699, longitude: 139.7048, gpsSource: .header)
        XCTAssertFalse(header.shouldResetMisplacedGPS)
        let user = MediaMetadataSnapshot(latitude: 35.6699, longitude: 139.7048, gpsSource: .user)
        XCTAssertFalse(user.shouldResetMisplacedGPS)
    }

    func testClearMisplacedGPSRewritesWarehouse() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("rolltag-gps-reset-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let db = try WarehouseDatabase(rootURL: root, warehouseID: UUID())
        let zero = sampleSnapshot(id: UUID(), path: "zero.jpg", latitude: 0, longitude: 0, source: .header)
        let guessed = sampleSnapshot(id: UUID(), path: "guess.jpg", latitude: 42.7, longitude: 141.6, source: .itinerary)
        let keep = sampleSnapshot(id: UUID(), path: "keep.jpg", latitude: 35.67, longitude: 139.70, source: .header)
        try db.insert(zero)
        try db.insert(guessed)
        try db.insert(keep)
        XCTAssertNil(try db.allFootage().first(where: { $0.filename == "zero.jpg" })?.latitude)
        let cleared = try db.clearMisplacedGPS()
        XCTAssertEqual(Set(cleared), [guessed.id])
        let loaded = Dictionary(uniqueKeysWithValues: try db.allFootage().map { ($0.filename, $0) })
        XCTAssertNil(loaded["guess.jpg"]?.latitude)
        XCTAssertEqual(loaded["keep.jpg"]?.latitude, 35.67)
        XCTAssertEqual(loaded["keep.jpg"]?.gpsSource, .header)
    }

    func testStoredGPSBeatsMissingLiveRead() {
        var footage = sampleFootage()
        footage.latitude = 1.37
        footage.longitude = 103.86
        footage.altitude = 12
        let payload = AITagSuggester.contextPayload(footage: footage, warehouseName: "Travel")
        let gps = payload["gps"] as? [String: Any]
        XCTAssertEqual(gps?["latitude"] as? Double, 1.37)
        XCTAssertEqual(gps?["longitude"] as? Double, 103.86)
    }

    func testCaptureMetadataRoundTripsInWarehouse() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("rolltag-capture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let db = try WarehouseDatabase(rootURL: root, warehouseID: UUID())
        let snap = FootageSnapshot(
            id: UUID(),
            relativePath: "a.mov",
            filename: "a.mov",
            size: 1,
            mtime: 1,
            contentHash: "h",
            phash: nil,
            status: .available,
            tags: [],
            userNotes: "",
            parentID: nil,
            duration: nil,
            width: nil,
            height: nil,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            needsReanalysis: false,
            capturedAtLocal: "2023-11-14T22:13:20",
            capturedAtHasTimeZone: false,
            capturedAtSource: .djiFilename,
            latitude: 1.5,
            longitude: 103.8,
            altitude: 9
        )
        try db.insert(snap)
        let loaded = try db.allFootage()[0]
        XCTAssertEqual(loaded.capturedAtSource, .djiFilename)
        XCTAssertEqual(loaded.capturedAtLocal, "2023-11-14T22:13:20")
        XCTAssertEqual(loaded.latitude, 1.5)
        XCTAssertEqual(loaded.longitude, 103.8)
        XCTAssertEqual(loaded.altitude, 9)
    }

    func testSkipImplausibleDefaultsTrueOnLegacyConfig() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("rolltag-pref-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appendingPathComponent("rolltag"), withIntermediateDirectories: true)
        let store = PreferenceStore(homeDirectory: home)
        try Data(#"{"version":1,"warehouses":[]}"#.utf8).write(to: store.configURL)
        let loaded = try store.load()
        XCTAssertTrue(loaded.ai.skipImplausibleCaptureDates)

        var file = loaded
        file = store.updateSkipImplausibleCaptureDates(false, in: file)
        try store.save(file)
        XCTAssertFalse(try store.load().ai.skipImplausibleCaptureDates)
    }

    private func sampleSnapshot(
        id: UUID,
        path: String,
        latitude: Double,
        longitude: Double,
        source: GPSSource
    ) -> FootageSnapshot {
        FootageSnapshot(
            id: id,
            relativePath: path,
            filename: (path as NSString).lastPathComponent,
            size: 1,
            mtime: 1,
            contentHash: "h",
            phash: nil,
            status: .available,
            tags: [],
            userNotes: "",
            parentID: nil,
            duration: nil,
            width: 10,
            height: 10,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            needsReanalysis: false,
            latitude: latitude,
            longitude: longitude,
            gpsSource: source
        )
    }

    private func sampleFootage() -> Footage {
        Footage(
            id: UUID(),
            warehouseID: UUID(),
            relativePath: "clip.mp4",
            filename: "clip.mp4",
            size: 10,
            mtime: 1,
            contentHash: nil,
            phash: nil,
            status: .available,
            duration: nil,
            width: nil,
            height: nil,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            parentID: nil,
            userNotes: "",
            tags: [],
            capturedAt: nil
        )
    }
}
