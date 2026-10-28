import XCTest
@testable import RollTag

final class ItineraryBuilderTests: XCTestCase {
    private let warehouse = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    func testUniqueNameAddsNumberWhenTaken() {
        let existing = [
            ItineraryRecord(
                id: UUID(),
                name: "東京",
                source: .timeline,
                gpxFilename: nil,
                folder: "",
                memberIDs: [],
                pendingIDs: [],
                createdAt: t0
            )
        ]
        XCTAssertEqual(ItineraryBuilder.uniqueName("東京", existing: existing), "東京 2")
        XCTAssertEqual(ItineraryBuilder.uniqueName("大阪", existing: existing), "大阪")
    }

    func testTimelineUsesGPSAnchorsAndAsksNearbyFilesWithoutGPS() {
        var withGPS = clip(id: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", relativePath: "tokyo/a.jpg")
        withGPS.capturedAt = t0
        withGPS.latitude = 35.6
        withGPS.longitude = 139.7
        withGPS.gpsSource = .header

        var laterGPS = clip(id: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB", relativePath: "tokyo/b.jpg")
        laterGPS.capturedAt = t0.addingTimeInterval(600)
        laterGPS.latitude = 35.7
        laterGPS.longitude = 139.8
        laterGPS.gpsSource = .header

        var nearby = clip(id: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD", relativePath: "tokyo/c.jpg")
        nearby.capturedAt = t0.addingTimeInterval(120)

        var far = clip(id: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE", relativePath: "tokyo/d.jpg")
        far.capturedAt = t0.addingTimeInterval(3 * 60 * 60)

        let record = ItineraryBuilder.buildTimeline(
            name: "東京",
            folder: "tokyo",
            footage: [withGPS, laterGPS, nearby, far]
        )
        XCTAssertEqual(record?.source, .timeline)
        XCTAssertEqual(Set(record?.memberIDs ?? []), [withGPS.id, laterGPS.id, nearby.id])
        XCTAssertEqual(record?.pendingIDs, [nearby.id])
    }

    func testGPXItineraryWritesMembersInSpanAndPendingJustOutside() {
        let track = GPXTrack(points: [
            GPXPoint(time: t0, latitude: 1, longitude: 2, altitude: nil),
            GPXPoint(time: t0.addingTimeInterval(120), latitude: 3, longitude: 4, altitude: nil),
        ])
        var inSpan = clip(id: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", relativePath: "japan/a.jpg")
        inSpan.capturedAt = t0.addingTimeInterval(30)
        inSpan.latitude = 1.5
        inSpan.longitude = 2.5
        inSpan.gpsSource = .gpx

        var nearby = clip(id: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB", relativePath: "japan/b.jpg")
        nearby.capturedAt = t0.addingTimeInterval(120 + 10 * 60)

        var far = clip(id: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD", relativePath: "japan/c.jpg")
        far.capturedAt = t0.addingTimeInterval(3 * 60 * 60)

        let record = ItineraryBuilder.buildGPX(
            name: "walk",
            folder: "japan",
            filename: "walk.gpx",
            footage: [inSpan, nearby, far],
            track: track,
            assignments: ["japan": "walk.gpx"],
            offsets: [:]
        )
        XCTAssertEqual(record.source, .gpx)
        XCTAssertEqual(Set(record.memberIDs), [inSpan.id, nearby.id])
        XCTAssertEqual(record.pendingIDs, [nearby.id])
    }

    func testSuggestedPointStaysAtTheRestaurantStay() {
        let lunch = gpsClip(
            id: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
            path: "tokyo/a.jpg",
            at: t0,
            latitude: 35.6699,
            longitude: 139.7048
        )
        let dessert = gpsClip(
            id: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
            path: "tokyo/b.jpg",
            at: t0.addingTimeInterval(1 * 3600 + 48 * 60),
            latitude: 35.6698,
            longitude: 139.7038
        )
        var video = clip(id: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD", relativePath: "tokyo/c.mp4")
        video.capturedAt = t0.addingTimeInterval(16 * 60)
        let guess = ItineraryBuilder.placeGuess(for: video, members: [lunch, dessert, video], offsets: [:])
        XCTAssertEqual(guess?.relation, .insideStay)
        XCTAssertEqual(guess?.point.latitude ?? 0, 35.67, accuracy: 0.01)
        XCTAssertEqual(guess?.point.longitude ?? 0, 139.70, accuracy: 0.01)
    }

    func testSuggestedPointIgnoresAirportSpikeBetweenRestaurantShots() {
        let lunch = gpsClip(
            id: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
            path: "tokyo/a.jpg",
            at: t0,
            latitude: 35.6699,
            longitude: 139.7048
        )
        let spike = gpsClip(
            id: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF",
            path: "tokyo/spike.jpg",
            at: t0.addingTimeInterval(13 * 60),
            latitude: 42.775,
            longitude: 141.692
        )
        let dessert = gpsClip(
            id: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC",
            path: "tokyo/b.jpg",
            at: t0.addingTimeInterval(1 * 3600 + 48 * 60),
            latitude: 35.6698,
            longitude: 139.7038
        )
        var video = clip(id: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD", relativePath: "tokyo/c.mp4")
        video.capturedAt = t0.addingTimeInterval(16 * 60)
        let guess = ItineraryBuilder.placeGuess(for: video, members: [lunch, spike, dessert, video], offsets: [:])
        XCTAssertEqual(guess?.point.latitude ?? 0, 35.67, accuracy: 0.02)
        XCTAssertLessThan(guess?.point.latitude ?? 99, 40, "must not snap to New Chitose")
    }

    func testSuggestedPointDoesNotFollowAFlightPath() {
        let tokyo = gpsClip(
            id: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
            path: "tokyo/a.jpg",
            at: t0,
            latitude: 35.6699,
            longitude: 139.7048
        )
        let chitose = gpsClip(
            id: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
            path: "hokkaido/b.jpg",
            at: t0.addingTimeInterval(2 * 3600),
            latitude: 42.775,
            longitude: 141.692
        )
        var video = clip(id: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD", relativePath: "tokyo/c.mp4")
        video.capturedAt = t0.addingTimeInterval(16 * 60)
        let guess = ItineraryBuilder.placeGuess(for: video, members: [tokyo, chitose, video], offsets: [:])
        XCTAssertEqual(guess?.relation, .insideStay)
        XCTAssertEqual(guess?.point.latitude ?? 0, 35.6699, accuracy: 0.0001)
    }

    func testGapBetweenStaysDefaultsToTheCloserStay() {
        let tokyo = gpsClip(
            id: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
            path: "tokyo/a.jpg",
            at: t0,
            latitude: 35.6699,
            longitude: 139.7048
        )
        let chitose = gpsClip(
            id: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
            path: "hokkaido/b.jpg",
            at: t0.addingTimeInterval(3 * 3600),
            latitude: 42.775,
            longitude: 141.692
        )
        var nearerTokyo = clip(id: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD", relativePath: "gap/a.mp4")
        nearerTokyo.capturedAt = t0.addingTimeInterval(40 * 60)
        var nearerChitose = clip(id: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE", relativePath: "gap/b.mp4")
        nearerChitose.capturedAt = t0.addingTimeInterval(3 * 3600 - 40 * 60)
        let members = [tokyo, chitose, nearerTokyo, nearerChitose]
        let first = ItineraryBuilder.placeGuess(for: nearerTokyo, members: members, offsets: [:])
        XCTAssertEqual(first?.relation, .previousStay)
        XCTAssertEqual(first?.point.latitude ?? 0, 35.6699, accuracy: 0.0001)
        XCTAssertNotNil(first?.next)
        let second = ItineraryBuilder.placeGuess(for: nearerChitose, members: members, offsets: [:])
        XCTAssertEqual(second?.relation, .nextStay)
        XCTAssertEqual(second?.point.latitude ?? 0, 42.775, accuracy: 0.0001)
        XCTAssertNotNil(second?.previous)

        XCTAssertNil(ItineraryBuilder.mapCoordinate(for: nearerTokyo, guess: first, preview: nil))
        let previewed = ItineraryBuilder.mapCoordinate(
            for: nearerTokyo,
            guess: first,
            preview: ItineraryGapPreview(footageID: nearerTokyo.id, relation: .previousStay)
        )
        XCTAssertEqual(previewed?.latitude ?? 0, 35.6699, accuracy: 0.0001)
        XCTAssertEqual(previewed?.guessed, true)
        let otherStay = ItineraryBuilder.mapCoordinate(
            for: nearerTokyo,
            guess: first,
            preview: ItineraryGapPreview(footageID: nearerTokyo.id, relation: .nextStay)
        )
        XCTAssertEqual(otherStay?.latitude ?? 0, 42.775, accuracy: 0.0001)
    }

    func testHoursAfterLastStayStillOffersPreviousStay() {
        let chitose = gpsClip(
            id: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
            path: "hokkaido/a.jpg",
            at: t0,
            latitude: 42.775,
            longitude: 141.692
        )
        var later = clip()
        later.capturedAt = t0.addingTimeInterval(3 * 3600)
        let guess = ItineraryBuilder.placeGuess(for: later, members: [chitose, later], offsets: [:])
        XCTAssertEqual(guess?.relation, .previousStay)
        XCTAssertEqual(guess?.point.latitude ?? 0, 42.775, accuracy: 0.0001)
        XCTAssertNil(guess?.next)
    }

    func testPocket3FilenameClockAlignsToJapanGPSPhotos() {
        let lunch = gpsClip(
            id: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
            path: "tokyo/IMG_4580.heic",
            at: Date(timeIntervalSince1970: 1_788_320_165),
            latitude: 35.6698,
            longitude: 139.7035
        )
        var lunchWithZone = lunch
        lunchWithZone.capturedAtLocal = "2026-09-02T12:36:05"
        lunchWithZone.capturedAtHasTimeZone = true

        let evening = gpsClip(
            id: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
            path: "hokkaido/IMG_0401.MOV",
            at: Date(timeIntervalSince1970: 1_788_351_744 + 24 * 60),
            latitude: 43.06,
            longitude: 141.35
        )
        var eveningWithZone = evening
        eveningWithZone.capturedAtLocal = "2026-09-02T21:46:24"
        eveningWithZone.capturedAtHasTimeZone = true

        var pocket = clip(id: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD", relativePath: "pocket3/DJI_20260902122224_0094_D.MP4")
        pocket.capturedAt = Date(timeIntervalSince1970: 1_788_351_744)
        pocket.capturedAtLocal = "2026-09-02T12:22:24"
        pocket.capturedAtHasTimeZone = false
        pocket.capturedAtSource = .djiFilename

        let guess = ItineraryBuilder.placeGuess(
            for: pocket,
            members: [lunchWithZone, eveningWithZone, pocket],
            offsets: [:]
        )
        XCTAssertEqual(guess?.relation, .insideStay)
        XCTAssertEqual(guess?.point.latitude ?? 0, 35.6698, accuracy: 0.0001)
        XCTAssertLessThan(guess?.point.latitude ?? 99, 40, "must not follow the unaligned clock to Sapporo")
    }

    func testEditedExportInheritsGPSFromLookalikeEarlierPhoto() {
        let original = gpsClip(
            id: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
            path: "tokyo/IMG_4580.heic",
            at: t0,
            latitude: 35.6698,
            longitude: 139.7035
        )
        var originalHashed = original
        originalHashed.phash = String(repeating: "10", count: 32)

        var edited = clip(id: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD", relativePath: "export/lunch.jpg")
        edited.capturedAt = t0.addingTimeInterval(6 * 3600)
        edited.capturedAtSource = .fileDate
        edited.phash = String(repeating: "10", count: 32)

        let guess = ItineraryBuilder.placeGuess(for: edited, members: [originalHashed, edited], offsets: [:])
        XCTAssertEqual(guess?.relation, .editedCopy)
        XCTAssertEqual(guess?.editedFromID, originalHashed.id)
        XCTAssertEqual(guess?.point.latitude ?? 0, 35.6698, accuracy: 0.0001)

        var capture = edited.captureMetadata
        capture.latitude = guess?.point.latitude
        capture.longitude = guess?.point.longitude
        capture.gpsSource = .itinerary
        let applied = ItineraryBuilder.applyingOriginalCapture(originalHashed, to: capture)
        XCTAssertEqual(applied.capturedAt, t0)
        XCTAssertEqual(applied.capturedAtSource, .original)
        XCTAssertEqual(applied.latitude ?? 0, 35.6698, accuracy: 0.0001)
        XCTAssertEqual(TagAssignment.retouch.category, "style")
        XCTAssertEqual(TagAssignment.retouch.value, "retouch")
    }

    func testRestoringPendingPutsClearedMembersBack() {
        let member = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let other = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let record = ItineraryRecord(
            id: UUID(),
            name: "東京",
            source: .timeline,
            gpxFilename: nil,
            folder: "",
            memberIDs: [member, other],
            pendingIDs: [other],
            createdAt: t0
        )
        let restored = ItineraryBuilder.restoringPending([record], clearedIDs: [member])
        XCTAssertEqual(Set(restored[0].pendingIDs), [member, other])
    }

    func testGuessTrackPrefersHeaderGPSOverGPXFilledAirport() {
        var restaurant = clip(id: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", relativePath: "tokyo/a.jpg")
        restaurant.capturedAt = t0
        restaurant.latitude = 35.6699
        restaurant.longitude = 139.7048
        restaurant.gpsSource = .header

        var gpxAirport = clip(id: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB", relativePath: "tokyo/b.jpg")
        gpxAirport.capturedAt = t0.addingTimeInterval(600)
        gpxAirport.latitude = 42.775
        gpxAirport.longitude = 141.692
        gpxAirport.gpsSource = .gpx

        let track = ItineraryBuilder.guessTrack(members: [restaurant, gpxAirport], fallbackGPX: nil)
        XCTAssertEqual(track?.points.count, 1)
        XCTAssertEqual(track?.points.first?.latitude ?? 0, 35.6699, accuracy: 0.0001)
    }

    func testItineraryFilterShowsOnlyMembers() {
        let itineraryID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let member = clip(id: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
        let outsider = clip(id: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")
        let itineraries = [
            ItineraryRecord(
                id: itineraryID,
                name: "東京",
                source: .timeline,
                gpxFilename: nil,
                folder: "",
                memberIDs: [member.id],
                pendingIDs: [],
                createdAt: t0
            )
        ]
        let selection = SidebarSelection.itinerary(warehouse, itineraryID)
        XCTAssertTrue(
            FootageFilter.include(
                footage: member,
                isOnline: true,
                selection: selection,
                isDuplicate: false,
                itineraries: itineraries
            )
        )
        XCTAssertFalse(
            FootageFilter.include(
                footage: outsider,
                isOnline: true,
                selection: selection,
                isDuplicate: false,
                itineraries: itineraries
            )
        )
    }

    func testMapCoordinatePrefersStoredGPSThenGuess() {
        var stored = clip()
        stored.latitude = 25.0
        stored.longitude = 121.5
        let guess = GPXPoint(time: t0, latitude: 1, longitude: 2, altitude: nil)
        let fromStored = ItineraryBuilder.mapCoordinate(for: stored, suggested: guess)
        XCTAssertEqual(fromStored?.latitude, 25.0)
        XCTAssertEqual(fromStored?.longitude, 121.5)
        XCTAssertEqual(fromStored?.guessed, false)

        var pending = clip()
        let fromGuess = ItineraryBuilder.mapCoordinate(for: pending, suggested: guess)
        XCTAssertEqual(fromGuess?.latitude, 1)
        XCTAssertEqual(fromGuess?.longitude, 2)
        XCTAssertEqual(fromGuess?.guessed, true)
        XCTAssertNil(ItineraryBuilder.mapCoordinate(for: pending, suggested: nil))
    }

    private func gpsClip(
        id: String,
        path: String,
        at date: Date,
        latitude: Double,
        longitude: Double
    ) -> Footage {
        var item = clip(id: id, relativePath: path)
        item.capturedAt = date
        item.capturedAtHasTimeZone = true
        item.latitude = latitude
        item.longitude = longitude
        item.gpsSource = .header
        return item
    }

    private func clip(
        id: String = "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
        relativePath: String = "clip.jpg"
    ) -> Footage {
        Footage(
            id: UUID(uuidString: id)!,
            warehouseID: warehouse,
            relativePath: relativePath,
            filename: (relativePath as NSString).lastPathComponent,
            size: 1,
            mtime: 1,
            contentHash: "h",
            phash: nil,
            status: .available,
            duration: nil,
            width: 10,
            height: 10,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            parentID: nil,
            userNotes: "",
            tags: [],
            capturedAt: nil
        )
    }
}

final class ItineraryMapCameraTests: XCTestCase {
    func testFitAllPinsPadsTheSpanToShowEveryPoint() {
        let region = ItineraryMapCamera.region(fitting: [
            (25.0, 121.5),
            (25.1, 121.6),
        ])
        XCTAssertEqual(region?.latitude ?? 0, 25.05, accuracy: 0.0001)
        XCTAssertEqual(region?.longitude ?? 0, 121.55, accuracy: 0.0001)
        XCTAssertEqual(region?.latitudeDelta ?? 0, 0.1 * ItineraryMapCamera.padding, accuracy: 0.0001)
        XCTAssertEqual(region?.longitudeDelta ?? 0, 0.1 * ItineraryMapCamera.padding, accuracy: 0.0001)
    }

    func testSinglePinUsesACloseFocus() {
        let region = ItineraryMapCamera.region(fitting: [(35.6, 139.7)])
        XCTAssertEqual(region?.latitudeDelta, ItineraryMapCamera.singleFocusDelta)
        XCTAssertEqual(region?.longitudeDelta, ItineraryMapCamera.singleFocusDelta)
        let focused = ItineraryMapCamera.region(focusing: (35.6, 139.7))
        XCTAssertEqual(focused.latitude, 35.6)
        XCTAssertEqual(focused.longitude, 139.7)
    }

    func testEmptyPointsHaveNoRegion() {
        XCTAssertNil(ItineraryMapCamera.region(fitting: []))
    }

    func testCloseZoomStopsClustering() {
        XCTAssertTrue(ItineraryMapCamera.clustersPins(latitudeDelta: 1.0))
        XCTAssertTrue(ItineraryMapCamera.clustersPins(latitudeDelta: 0.05))
        XCTAssertFalse(ItineraryMapCamera.clustersPins(latitudeDelta: 0.00009))
        XCTAssertFalse(ItineraryMapCamera.clustersPins(latitudeDelta: 0.002))
    }

    func testStackedPinsSpreadAroundACircle() {
        XCTAssertEqual(ItineraryMapCamera.spreadOffsets(count: 1), [.zero])
        let eight = ItineraryMapCamera.spreadOffsets(count: 8)
        XCTAssertEqual(eight.count, 8)
        XCTAssertGreaterThan(abs(eight[0].x) + abs(eight[0].y), 10)
        XCTAssertEqual(Set(eight.map { "\($0.x.rounded())|\($0.y.rounded())" }).count, 8)
    }

    func testRejectsWorldSizedSavedCameraWhenContentIsLocal() {
        let saved = FittedMapRegion(latitude: 0, longitude: 0, latitudeDelta: 80, longitudeDelta: 160)
        let fit = FittedMapRegion(latitude: 35.6, longitude: 139.7, latitudeDelta: 0.04, longitudeDelta: 0.04)
        XCTAssertFalse(saved.isPlausible(forContent: fit))
        XCTAssertTrue(fit.isUsable)
    }
}

final class ItineraryRouteTests: XCTestCase {
    func testLandHopUsesStraightDashedSegment() {
        let taipei = (latitude: 25.033, longitude: 121.565)
        let kaohsiung = (latitude: 22.627, longitude: 120.301)
        XCTAssertEqual(ItineraryRoute.kind(from: taipei, to: kaohsiung), .land)
        let segments = ItineraryRoute.segments(connecting: [taipei, kaohsiung])
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].kind, .land)
        XCTAssertEqual(segments[0].points.count, 2)
    }

    func testSeaHopUsesGeodesicArc() {
        let taipei = (latitude: 25.033, longitude: 121.565)
        let brisbane = (latitude: -27.470, longitude: 153.026)
        XCTAssertEqual(ItineraryRoute.kind(from: taipei, to: brisbane), .sea)
        let segments = ItineraryRoute.segments(connecting: [taipei, brisbane])
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].kind, .sea)
        XCTAssertGreaterThan(segments[0].points.count, 2)
        let mid = segments[0].points[segments[0].points.count / 2]
        XCTAssertLessThan(mid.latitude, taipei.latitude)
        XCTAssertGreaterThan(mid.latitude, brisbane.latitude)
    }

    func testNearbyOceanPointsStayStraight() {
        let a = (latitude: 0.0, longitude: 0.0)
        let b = (latitude: 0.01, longitude: 0.01)
        XCTAssertEqual(ItineraryRoute.kind(from: a, to: b), .land)
    }

    func testBrisbaneSuburbsStayOnLand() {
        let northgate = (latitude: -27.391, longitude: 153.068)
        let clayfield = (latitude: -27.418, longitude: 153.057)
        XCTAssertEqual(ItineraryRoute.kind(from: northgate, to: clayfield), .land)
    }

    func testIgnoresExaggeratedJumpInABurst() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let tokyo = ItineraryRoute.TimedPoint(latitude: 35.62, longitude: 139.78, time: t0)
        let newYork = ItineraryRoute.TimedPoint(latitude: 40.64, longitude: -73.78, time: t0.addingTimeInterval(2))
        XCTAssertFalse(ItineraryRoute.isPlausibleHop(from: tokyo, to: newYork))
        XCTAssertTrue(ItineraryRoute.segments(connecting: [tokyo, newYork]).isEmpty)
    }

    func testDropsASpikeAndReconnectsNearbyShots() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let first = ItineraryRoute.TimedPoint(latitude: 35.620, longitude: 139.780, time: t0)
        let spike = ItineraryRoute.TimedPoint(latitude: 1.35, longitude: 103.82, time: t0.addingTimeInterval(1))
        let next = ItineraryRoute.TimedPoint(latitude: 35.621, longitude: 139.781, time: t0.addingTimeInterval(8))
        let segments = ItineraryRoute.segments(connecting: [first, spike, next])
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].kind, .land)
        XCTAssertEqual(segments[0].points.count, 2)
        XCTAssertEqual(segments[0].points[0].latitude, 35.620, accuracy: 0.0001)
        XCTAssertEqual(segments[0].points[1].latitude, 35.621, accuracy: 0.0001)
    }

    func testKeepsARealFlightSpreadOverHours() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let tokyo = ItineraryRoute.TimedPoint(latitude: 35.62, longitude: 139.78, time: t0)
        let taipei = ItineraryRoute.TimedPoint(latitude: 25.08, longitude: 121.23, time: t0.addingTimeInterval(3 * 60 * 60))
        XCTAssertTrue(ItineraryRoute.isPlausibleHop(from: tokyo, to: taipei))
        XCTAssertFalse(ItineraryRoute.segments(connecting: [tokyo, taipei]).isEmpty)
    }

    func testFitIgnoresTheSpike() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let points = [
            ItineraryRoute.TimedPoint(latitude: 35.62, longitude: 139.78, time: t0),
            ItineraryRoute.TimedPoint(latitude: 0, longitude: 0, time: t0.addingTimeInterval(1)),
            ItineraryRoute.TimedPoint(latitude: 35.63, longitude: 139.79, time: t0.addingTimeInterval(12)),
        ]
        let fit = ItineraryRoute.coordinatesForFit(from: points)
        XCTAssertEqual(fit.count, 2)
        XCTAssertTrue(fit.allSatisfy { $0.latitude > 30 })
    }
}

final class ItineraryMapRegionStoreTests: XCTestCase {
    func testSavedMapRegionRoundTripsInJSON() throws {
        var record = ItineraryRecord(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            name: "布里斯本",
            source: .timeline,
            gpxFilename: nil,
            folder: "",
            memberIDs: [],
            pendingIDs: [],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        record.savedMapRegion = FittedMapRegion(
            latitude: -27.4,
            longitude: 153.05,
            latitudeDelta: 0.12,
            longitudeDelta: 0.18
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode([record])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loaded = try decoder.decode([ItineraryRecord].self, from: data)
        XCTAssertEqual(loaded[0].savedMapRegion?.latitude ?? 0, -27.4, accuracy: 0.0001)
        XCTAssertEqual(loaded[0].savedMapRegion?.longitude ?? 0, 153.05, accuracy: 0.0001)
        XCTAssertEqual(loaded[0].savedMapRegion?.latitudeDelta ?? 0, 0.12, accuracy: 0.0001)
        XCTAssertEqual(loaded[0].savedMapRegion?.longitudeDelta ?? 0, 0.18, accuracy: 0.0001)
    }

    func testLegacyItineraryJSONHasNoSavedCamera() throws {
        let json = """
        [{"id":"11111111-1111-1111-1111-111111111111","name":"東京","source":"timeline","folder":"","memberIDs":[],"pendingIDs":[],"createdAt":"2023-11-14T22:13:20Z"}]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loaded = try decoder.decode([ItineraryRecord].self, from: Data(json.utf8))
        XCTAssertNil(loaded[0].savedMapRegion)
        XCTAssertEqual(loaded[0].name, "東京")
    }
}
