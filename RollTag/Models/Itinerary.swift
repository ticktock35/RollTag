import Foundation

enum ItinerarySource: String, Codable, Equatable, Hashable, Sendable {
    case gpx
    case timeline
}

struct ItineraryRecord: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var source: ItinerarySource
    var gpxFilename: String?
    var folder: String
    var memberIDs: [UUID]
    var pendingIDs: [UUID]
    var createdAt: Date
    var mapLatitude: Double? = nil
    var mapLongitude: Double? = nil
    var mapLatitudeDelta: Double? = nil
    var mapLongitudeDelta: Double? = nil

    var savedMapRegion: FittedMapRegion? {
        get {
            guard let mapLatitude, let mapLongitude, let mapLatitudeDelta, let mapLongitudeDelta else {
                return nil
            }
            return FittedMapRegion(
                latitude: mapLatitude,
                longitude: mapLongitude,
                latitudeDelta: mapLatitudeDelta,
                longitudeDelta: mapLongitudeDelta
            )
        }
        set {
            mapLatitude = newValue?.latitude
            mapLongitude = newValue?.longitude
            mapLatitudeDelta = newValue?.latitudeDelta
            mapLongitudeDelta = newValue?.longitudeDelta
        }
    }
}

struct ItineraryRenamePrompt: Identifiable, Equatable {
    var warehouseID: UUID
    var itineraryID: UUID
    var name: String

    var id: UUID { itineraryID }
}

enum ItineraryStore {
    static func load(root: URL) -> [ItineraryRecord] {
        let url = fileURL(root: root)
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ItineraryRecord].self, from: data)) ?? []
    }

    static func save(_ items: [ItineraryRecord], root: URL) throws {
        let url = fileURL(root: root)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(items).write(to: url, options: .atomic)
    }

    static func fileURL(root: URL) -> URL {
        root
            .appendingPathComponent(MediaConstants.rolltagDirectory)
            .appendingPathComponent(MediaConstants.itinerariesName)
    }
}

enum ItineraryBuilder {
    static let pendingPadding: TimeInterval = 30 * 60

    static func uniqueName(_ base: String, existing: [ItineraryRecord]) -> String {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let seed = trimmed.isEmpty ? "行程" : trimmed
        let names = Set(existing.map(\.name))
        if !names.contains(seed) { return seed }
        var index = 2
        while names.contains("\(seed) \(index)") {
            index += 1
        }
        return "\(seed) \(index)"
    }

    static func timelineTrack(from footage: [Footage]) -> GPXTrack {
        let points = footage
            .compactMap { item -> GPXPoint? in
                guard item.captureMetadata.hasGPS, let time = item.capturedAt else { return nil }
                guard let latitude = item.latitude, let longitude = item.longitude else { return nil }
                return GPXPoint(time: time, latitude: latitude, longitude: longitude, altitude: item.altitude)
            }
            .sorted { $0.time < $1.time }
        return GPXTrack(points: points)
    }

    static func buildTimeline(name: String, folder: String, footage: [Footage]) -> ItineraryRecord? {
        let scoped = scopedMedia(footage, folder: folder)
        guard !stays(from: scoped).isEmpty else { return nil }
        let membership = membersAndPending(scoped: scoped, offsets: [:])
        return ItineraryRecord(
            id: UUID(),
            name: name,
            source: .timeline,
            gpxFilename: nil,
            folder: WarehouseFolderTree.normalize(folder),
            memberIDs: membership.members,
            pendingIDs: membership.pending,
            createdAt: Date()
        )
    }

    static func buildGPX(
        name: String,
        folder: String,
        filename: String,
        footage: [Footage],
        track: GPXTrack,
        assignments: [String: String],
        offsets: [String: FolderTimeOffset]
    ) -> ItineraryRecord {
        let scoped = scopedMedia(footage, folder: folder)
        var members: [UUID] = []
        var pending: [UUID] = []
        for item in scoped {
            let onTrack = GPXMatcher.belongs(
                footage: item,
                filename: filename,
                track: track,
                assignments: assignments,
                offsets: offsets
            )
            let nearby = isInPaddedWindow(item, track: track, offsets: offsets)
            let edited = placeGuess(
                for: item,
                members: scoped,
                offsets: offsets,
                fallbackGPX: track
            )?.relation == .editedCopy
            guard onTrack || nearby || edited else { continue }
            members.append(item.id)
            if !item.captureMetadata.hasGPS {
                pending.append(item.id)
            }
        }
        return ItineraryRecord(
            id: UUID(),
            name: name,
            source: .gpx,
            gpxFilename: filename,
            folder: WarehouseFolderTree.normalize(folder),
            memberIDs: members,
            pendingIDs: pending,
            createdAt: Date()
        )
    }

    static func mapCoordinate(
        for footage: Footage,
        suggested: GPXPoint?
    ) -> (latitude: Double, longitude: Double, guessed: Bool)? {
        mapCoordinate(for: footage, guess: suggested.map {
            ItineraryPlaceGuess(point: $0, relation: .insideStay, previous: nil, next: nil, editedFromID: nil)
        }, preview: nil)
    }

    static func mapCoordinate(
        for footage: Footage,
        guess: ItineraryPlaceGuess?,
        preview: ItineraryGapPreview?
    ) -> (latitude: Double, longitude: Double, guessed: Bool)? {
        if footage.captureMetadata.hasGPS, let latitude = footage.latitude, let longitude = footage.longitude {
            return (latitude, longitude, false)
        }
        guard let guess else { return nil }
        if guess.isGap {
            guard let preview, preview.footageID == footage.id,
                  let stay = guess.stay(for: preview.relation),
                  MediaMetadata.isUsableGPS(latitude: stay.latitude, longitude: stay.longitude)
            else { return nil }
            return (stay.latitude, stay.longitude, true)
        }
        guard MediaMetadata.isUsableGPS(latitude: guess.point.latitude, longitude: guess.point.longitude) else {
            return nil
        }
        return (guess.point.latitude, guess.point.longitude, true)
    }

    static func guessTrack(members: [Footage], fallbackGPX: GPXTrack?) -> GPXTrack? {
        let reliable = members.filter(isReliableGPSAnchor)
        let withGPS = members.filter { $0.captureMetadata.hasGPS }
        let fromPhotos = timelineTrack(from: reliable.isEmpty ? withGPS : reliable)
        if !fromPhotos.points.isEmpty { return fromPhotos }
        if let fallbackGPX, !fallbackGPX.points.isEmpty { return fallbackGPX }
        return nil
    }

    static func isReliableGPSAnchor(_ footage: Footage) -> Bool {
        guard footage.captureMetadata.hasGPS else { return false }
        switch footage.captureMetadata.resolvedGPSSource {
        case .header, .user:
            return true
        case .gpx, .itinerary:
            return false
        case .none:
            return false
        }
    }

    static func cleanedGuessAnchors(_ points: [GPXPoint]) -> [GPXPoint] {
        let timed = points.map {
            ItineraryRoute.TimedPoint(latitude: $0.latitude, longitude: $0.longitude, time: $0.time)
        }
        let kept = ItineraryRoute.withoutSpikes(timed)
        var remaining = points
        return kept.compactMap { point in
            guard let index = remaining.firstIndex(where: {
                $0.time == point.time
                    && abs($0.latitude - point.latitude) < 1e-7
                    && abs($0.longitude - point.longitude) < 1e-7
            }) else { return nil }
            return remaining.remove(at: index)
        }
    }

    static func restoringPending(_ items: [ItineraryRecord], clearedIDs: Set<UUID>) -> [ItineraryRecord] {
        items.map { record in
            var next = record
            let extra = next.memberIDs.filter { clearedIDs.contains($0) }
            for id in extra where !next.pendingIDs.contains(id) {
                next.pendingIDs.append(id)
            }
            return next
        }
    }

    static func membersAndPending(
        scoped: [Footage],
        offsets: [String: FolderTimeOffset],
        track: GPXTrack? = nil
    ) -> (members: [UUID], pending: [UUID]) {
        let zone = shootingTimeZone(from: scoped)
        let clustered = stays(from: scoped, offsets: offsets)
        let windowStart = clustered.first.map { $0.start.addingTimeInterval(-pendingPadding) }
        let windowEnd = clustered.last.map { $0.end.addingTimeInterval(pendingPadding) }
        var members: [UUID] = []
        var pending: [UUID] = []
        for item in scoped {
            if item.captureMetadata.hasGPS {
                members.append(item.id)
                continue
            }
            if placeGuess(for: item, members: scoped, offsets: offsets, fallbackGPX: track)?.relation == .editedCopy {
                members.append(item.id)
                pending.append(item.id)
                continue
            }
            if let track, isInPaddedWindow(item, track: track, offsets: offsets) {
                members.append(item.id)
                pending.append(item.id)
                continue
            }
            guard let time = alignedInstant(of: item, zone: zone, offsets: offsets),
                  let windowStart, let windowEnd,
                  time >= windowStart, time <= windowEnd
            else { continue }
            members.append(item.id)
            pending.append(item.id)
        }
        return (members, pending)
    }

    static func isInPaddedWindow(_ footage: Footage, track: GPXTrack, offsets: [String: FolderTimeOffset]) -> Bool {
        guard let start = track.start, let end = track.end else { return false }
        guard let adjusted = GPXMatcher.adjustedCapture(of: footage, offsets: offsets) else { return false }
        return adjusted >= start.addingTimeInterval(-pendingPadding)
            && adjusted <= end.addingTimeInterval(pendingPadding)
    }

    private static func scopedMedia(_ footage: [Footage], folder: String) -> [Footage] {
        let normalized = WarehouseFolderTree.normalize(folder)
        return footage.filter { item in
            item.status == .available
                && (item.mediaKind == .image || item.mediaKind == .video)
                && WarehouseFolderTree.contains(directoryPath: item.directoryPath, folder: normalized)
        }
    }
}
