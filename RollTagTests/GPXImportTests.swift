import XCTest
@testable import RollTag

final class GPXImportTests: XCTestCase {
    func testParsesTrackPointsAndWaypointsWithTime() throws {
        let xml = """
        <?xml version="1.0"?>
        <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
          <wpt lat="1.3000" lon="103.8000"><time>2024-01-01T00:00:00Z</time><ele>12</ele></wpt>
          <trk><trkseg>
            <trkpt lat="1.3100" lon="103.8100"><time>2024-01-01T00:01:00Z</time><ele>14</ele></trkpt>
            <trkpt lat="1.3200" lon="103.8200"><time>2024-01-01T00:02:00Z</time></trkpt>
          </trkseg></trk>
        </gpx>
        """
        let track = try GPXDocument.parse(data: Data(xml.utf8))
        XCTAssertEqual(track.points.count, 3)
        XCTAssertEqual(track.points[0].latitude, 1.3, accuracy: 0.0001)
        XCTAssertEqual(track.points[0].altitude, 12)
        XCTAssertEqual(track.start, GPXDocument.parseGPXTime("2024-01-01T00:00:00Z"))
        XCTAssertEqual(track.end, GPXDocument.parseGPXTime("2024-01-01T00:02:00Z"))
    }

    func testInterpolatesBetweenPointsAndRejectsOutsideSpan() throws {
        let start = GPXDocument.parseGPXTime("2024-06-01T10:00:00Z")!
        let end = GPXDocument.parseGPXTime("2024-06-01T10:10:00Z")!
        let track = GPXTrack(points: [
            GPXPoint(time: start, latitude: 0, longitude: 0, altitude: 0),
            GPXPoint(time: end, latitude: 10, longitude: 20, altitude: 100),
        ])
        let mid = start.addingTimeInterval(5 * 60)
        let point = track.location(at: mid)
        XCTAssertEqual(point?.latitude ?? 0, 5, accuracy: 0.0001)
        XCTAssertEqual(point?.longitude ?? 0, 10, accuracy: 0.0001)
        XCTAssertEqual(point?.altitude ?? 0, 50, accuracy: 0.0001)
        XCTAssertNil(track.location(at: start.addingTimeInterval(-1)))
        XCTAssertNil(track.location(at: end.addingTimeInterval(1)))
        XCTAssertEqual(track.location(at: start)?.latitude, 0)
        XCTAssertEqual(track.location(at: end)?.latitude, 10)
    }

    func testMatcherSkipsExistingGPSAudioAndTimesOutsideTrack() {
        let t0 = GPXDocument.parseGPXTime("2024-06-01T10:00:00Z")!
        let track = GPXTrack(points: [
            GPXPoint(time: t0, latitude: 1, longitude: 2, altitude: nil),
            GPXPoint(time: t0.addingTimeInterval(120), latitude: 3, longitude: 4, altitude: nil),
        ])
        let files = [
            GPXEligibleFile(id: UUID(), relativePath: "trip/a.jpg", filename: "a.jpg", folder: "trip", capturedAt: t0.addingTimeInterval(30)),
            GPXEligibleFile(id: UUID(), relativePath: "trip/b.jpg", filename: "b.jpg", folder: "trip", capturedAt: t0.addingTimeInterval(400)),
        ]
        let hits = GPXMatcher.candidates(files: files, track: track, offsets: [:])
        XCTAssertEqual(hits.map(\.filename), ["a.jpg"])
        XCTAssertEqual(hits[0].latitude, 1.5, accuracy: 0.0001)
    }

    func testFolderOffsetBringsCaptureIntoTrack() {
        let t0 = GPXDocument.parseGPXTime("2024-06-01T10:00:00Z")!
        let track = GPXTrack(points: [
            GPXPoint(time: t0, latitude: 8, longitude: 9, altitude: 3),
            GPXPoint(time: t0.addingTimeInterval(60), latitude: 8.1, longitude: 9.1, altitude: 4),
        ])
        let file = GPXEligibleFile(
            id: UUID(),
            relativePath: "card/IMG_1.jpg",
            filename: "IMG_1.jpg",
            folder: "card",
            capturedAt: t0.addingTimeInterval(-5 * 60)
        )
        XCTAssertTrue(GPXMatcher.candidates(files: [file], track: track, offsets: [:]).isEmpty)
        let hits = GPXMatcher.candidates(files: [file], track: track, offsets: ["card": 5])
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].latitude, 8, accuracy: 0.0001)
        XCTAssertEqual(hits[0].altitude, 3)
        XCTAssertTrue(GPXMatcher.candidates(files: [file], track: track, offsets: ["other": 5]).isEmpty)
    }

    func testEligibleIgnoresGPSAudioAndUntimedFiles() {
        let time = Date(timeIntervalSince1970: 1_700_000_000)
        let photo = footage(path: "a.jpg", kindHint: "a.jpg", capturedAt: time, latitude: nil)
        let withGPS = footage(path: "b.jpg", kindHint: "b.jpg", capturedAt: time, latitude: 1.2, longitude: 103)
        let audio = footage(path: "c.m4a", kindHint: "c.m4a", capturedAt: time, latitude: nil)
        let untimed = footage(path: "d.jpg", kindHint: "d.jpg", capturedAt: nil, latitude: nil)
        let ids = Set(GPXMatcher.eligible(from: [photo, withGPS, audio, untimed]).map(\.filename))
        XCTAssertEqual(ids, ["a.jpg"])
    }

    func testMergingKeepsGPXWhenHeaderHasNoGPSAndHeaderWinsOtherwise() {
        var stored = MediaMetadataSnapshot(
            latitude: 1.1,
            longitude: 103.1,
            altitude: 10,
            capturedAt: Date(timeIntervalSince1970: 50),
            gpsSource: .gpx
        )
        let emptyLive = MediaMetadataSnapshot(capturedAt: Date(timeIntervalSince1970: 99))
        let kept = stored.merging(live: emptyLive, replaceTime: true)
        XCTAssertEqual(kept.latitude, 1.1)
        XCTAssertEqual(kept.gpsSource, .gpx)
        XCTAssertEqual(kept.capturedAt, Date(timeIntervalSince1970: 99))

        let header = MediaMetadataSnapshot(
            latitude: 2,
            longitude: 4,
            altitude: 20,
            capturedAt: Date(timeIntervalSince1970: 80),
            gpsSource: .header
        )
        let replaced = stored.merging(live: header, replaceTime: false)
        XCTAssertEqual(replaced.latitude, 2)
        XCTAssertEqual(replaced.gpsSource, .header)
        XCTAssertEqual(replaced.capturedAt, Date(timeIntervalSince1970: 50))
    }

    func testWarehouseRoundTripsGPXSource() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("rolltag-gpx-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let db = try WarehouseDatabase(rootURL: root, warehouseID: UUID())
        let snap = FootageSnapshot(
            id: UUID(),
            relativePath: "trip/a.jpg",
            filename: "a.jpg",
            size: 10,
            mtime: 1,
            contentHash: "h",
            phash: nil,
            status: .available,
            tags: [],
            userNotes: "",
            parentID: nil,
            duration: nil,
            width: 100,
            height: 80,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            needsReanalysis: false,
            latitude: 1.37,
            longitude: 103.86,
            altitude: 12,
            gpsSource: .gpx
        )
        try db.insert(snap)
        let loaded = try db.allFootage()[0]
        XCTAssertEqual(loaded.latitude, 1.37)
        XCTAssertEqual(loaded.gpsSource, .gpx)
        XCTAssertEqual(loaded.captureMetadata.resolvedGPSSource, .gpx)
    }

    func testOffsetStoreRoundTripAndTrackCopy() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("rolltag-off-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try GPXOffsetStore.save(["trip": 5, "": -1], root: root)
        XCTAssertEqual(GPXOffsetStore.load(root: root)["trip"], 5)
        XCTAssertEqual(GPXOffsetStore.load(root: root)[""], -1)

        let source = root.appendingPathComponent("walk.gpx")
        try Data("<gpx/>".utf8).write(to: source)
        let copied = try GPXOffsetStore.copyTrack(from: source, root: root)
        XCTAssertTrue(copied.path.contains("/.rolltag/gpx/walk.gpx"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: copied.path))
    }

    func testEmptyGPXThrows() {
        XCTAssertThrowsError(try GPXDocument.parse(data: Data("<gpx></gpx>".utf8))) { error in
            XCTAssertEqual(error as? GPXParseError, .empty)
        }
    }

    func testAssignedTrackPrefersMoreSpecificFolder() {
        let assignments = ["": "root.gpx", "japan": "tokyo.gpx"]
        XCTAssertEqual(GPXMatcher.assignedTrack(directoryPath: "", assignments: assignments), "root.gpx")
        XCTAssertEqual(GPXMatcher.assignedTrack(directoryPath: "japan", assignments: assignments), "tokyo.gpx")
        XCTAssertEqual(GPXMatcher.assignedTrack(directoryPath: "japan/shinjuku", assignments: assignments), "tokyo.gpx")
        XCTAssertEqual(GPXMatcher.assignedTrack(directoryPath: "korea", assignments: assignments), "root.gpx")
        XCTAssertNil(GPXMatcher.assignedTrack(directoryPath: "japan", assignments: [:]))
    }

    func testBelongsUsesAssignmentAndTrackSpan() {
        let t0 = GPXDocument.parseGPXTime("2024-06-01T10:00:00Z")!
        let track = GPXTrack(points: [
            GPXPoint(time: t0, latitude: 1, longitude: 2, altitude: nil),
            GPXPoint(time: t0.addingTimeInterval(120), latitude: 3, longitude: 4, altitude: nil),
        ])
        let assignments = ["japan": "walk.gpx"]
        let inSpan = footage(path: "japan/a.jpg", kindHint: "a.jpg", capturedAt: t0.addingTimeInterval(30), latitude: nil)
        let outside = footage(path: "japan/b.jpg", kindHint: "b.jpg", capturedAt: t0.addingTimeInterval(400), latitude: nil)
        let otherFolder = footage(path: "korea/c.jpg", kindHint: "c.jpg", capturedAt: t0.addingTimeInterval(30), latitude: nil)
        let nested = footage(path: "japan/tokyo/d.jpg", kindHint: "d.jpg", capturedAt: t0.addingTimeInterval(40), latitude: 1.2, longitude: 103)
        let audio = footage(path: "japan/e.m4a", kindHint: "e.m4a", capturedAt: t0.addingTimeInterval(30), latitude: nil)
        XCTAssertTrue(GPXMatcher.belongs(footage: inSpan, filename: "walk.gpx", track: track, assignments: assignments, offsets: [:]))
        XCTAssertFalse(GPXMatcher.belongs(footage: outside, filename: "walk.gpx", track: track, assignments: assignments, offsets: [:]))
        XCTAssertFalse(GPXMatcher.belongs(footage: otherFolder, filename: "walk.gpx", track: track, assignments: assignments, offsets: [:]))
        XCTAssertTrue(GPXMatcher.belongs(footage: nested, filename: "walk.gpx", track: track, assignments: assignments, offsets: [:]))
        XCTAssertFalse(GPXMatcher.belongs(footage: audio, filename: "walk.gpx", track: track, assignments: assignments, offsets: [:]))
        let childWins = ["japan": "walk.gpx", "japan/tokyo": "other.gpx"]
        XCTAssertFalse(GPXMatcher.belongs(footage: nested, filename: "walk.gpx", track: track, assignments: childWins, offsets: [:]))
    }

    func testShouldWriteGPSSkipsHeaderButAllowsGPXRewrite() {
        XCTAssertTrue(GPXMatcher.shouldWriteGPS(MediaMetadataSnapshot()))
        XCTAssertFalse(
            GPXMatcher.shouldWriteGPS(
                MediaMetadataSnapshot(latitude: 1, longitude: 2, gpsSource: .header)
            )
        )
        XCTAssertTrue(
            GPXMatcher.shouldWriteGPS(
                MediaMetadataSnapshot(latitude: 1, longitude: 2, gpsSource: .gpx)
            )
        )
    }

    func testAssignmentStoreRoundTripsFolderMap() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("rolltag-gpx-assign-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try GPXAssignmentStore.save(["japan": "walk.gpx", "": "root.gpx"], root: root)
        let loaded = GPXAssignmentStore.load(root: root)
        XCTAssertEqual(loaded["japan"], "walk.gpx")
        XCTAssertEqual(loaded[""], "root.gpx")
        try? FileManager.default.removeItem(at: root)
    }

    private func footage(
        path: String,
        kindHint: String,
        capturedAt: Date?,
        latitude: Double?,
        longitude: Double? = nil
    ) -> Footage {
        Footage(
            id: UUID(),
            warehouseID: UUID(),
            relativePath: path,
            filename: kindHint,
            size: 1000,
            mtime: 1,
            contentHash: "h",
            phash: nil,
            status: .available,
            duration: nil,
            width: nil,
            height: nil,
            createdAt: Date(),
            updatedAt: Date(),
            parentID: nil,
            userNotes: "",
            tags: [],
            capturedAt: capturedAt,
            latitude: latitude,
            longitude: longitude ?? (latitude == nil ? nil : 1)
        )
    }
}
