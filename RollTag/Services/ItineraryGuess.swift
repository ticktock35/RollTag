import Foundation

struct ItineraryStay: Equatable, Hashable, Sendable {
    var start: Date
    var end: Date
    var latitude: Double
    var longitude: Double
    var altitude: Double?

    func contains(_ date: Date, pad: TimeInterval) -> Bool {
        date >= start.addingTimeInterval(-pad) && date <= end.addingTimeInterval(pad)
    }

    func point(at date: Date) -> GPXPoint {
        GPXPoint(time: date, latitude: latitude, longitude: longitude, altitude: altitude)
    }

    var timeText: String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: start)
    }
}

enum ItineraryGuessRelation: Equatable, Sendable {
    case insideStay
    case previousStay
    case nextStay
    case editedCopy
}

struct ItineraryGapPreview: Equatable, Sendable {
    var footageID: UUID
    var relation: ItineraryGuessRelation
}

struct ItineraryPlaceGuess: Equatable, Sendable {
    var point: GPXPoint
    var relation: ItineraryGuessRelation
    var previous: ItineraryStay?
    var next: ItineraryStay?
    var editedFromID: UUID?

    var isGap: Bool {
        relation == .previousStay || relation == .nextStay
    }

    func stay(for relation: ItineraryGuessRelation) -> ItineraryStay? {
        switch relation {
        case .previousStay: previous
        case .nextStay: next
        default: nil
        }
    }
}

extension ItineraryBuilder {
    /// 同一段「待在這裡」的半徑。餐廳、公園內走動算一段；跨到下一區就切斷。
    static let stayRadiusMeters: Double = 500
    /// 進出這段前後還算在這裡（結帳、走出門）。
    static let stayPad: TimeInterval = 20 * 60
    /// 修圖檔畫面指紋最多差幾 bit（64 bit 平均 hash）。搜尋用 8，這裡嚴一點。
    static let editedPhashMaxDistance = 6
    /// 時間明顯晚於原圖才當成匯出／修圖，避免連拍互認。
    static let editedMinLag: TimeInterval = 20 * 60
    static let retouchTag = TagAssignment.retouch

    static func placeGuess(
        for footage: Footage,
        members: [Footage],
        offsets: [String: FolderTimeOffset],
        fallbackGPX: GPXTrack? = nil
    ) -> ItineraryPlaceGuess? {
        let zone = shootingTimeZone(from: members)
        if let edited = editedOriginal(for: footage, in: members, zone: zone, offsets: offsets) {
            let time = alignedInstant(of: footage, zone: zone, offsets: offsets) ?? edited.point.time
            return ItineraryPlaceGuess(
                point: GPXPoint(
                    time: time,
                    latitude: edited.point.latitude,
                    longitude: edited.point.longitude,
                    altitude: edited.point.altitude
                ),
                relation: .editedCopy,
                previous: nil,
                next: nil,
                editedFromID: edited.id
            )
        }
        guard let time = alignedInstant(of: footage, zone: zone, offsets: offsets) else { return nil }
        if let fallbackGPX, let point = fallbackGPX.location(at: time) {
            return ItineraryPlaceGuess(
                point: point,
                relation: .insideStay,
                previous: nil,
                next: nil,
                editedFromID: nil
            )
        }
        let stays = stays(from: members, offsets: offsets)
        return placeGuess(at: time, stays: stays)
    }

    static func suggestedPoint(
        for footage: Footage,
        members: [Footage],
        offsets: [String: FolderTimeOffset],
        fallbackGPX: GPXTrack? = nil
    ) -> GPXPoint? {
        placeGuess(for: footage, members: members, offsets: offsets, fallbackGPX: fallbackGPX)?.point
    }

    /// 修圖檔確認後：帶入原圖拍攝時間（倉庫 metadata，不改原檔）。
    static func applyingOriginalCapture(_ original: Footage, to capture: MediaMetadataSnapshot) -> MediaMetadataSnapshot {
        var next = capture
        guard let time = original.capturedAt else { return next }
        next.capturedAt = time
        next.capturedAtLocal = original.capturedAtLocal
        next.capturedAtHasTimeZone = original.capturedAtHasTimeZone
        next.capturedAtSource = .original
        return next
    }

    static func stays(
        from members: [Footage],
        offsets: [String: FolderTimeOffset] = [:]
    ) -> [ItineraryStay] {
        clusterStays(cleanedGuessAnchors(gpsAnchors(from: members, offsets: offsets)))
    }

    static func placeGuess(at date: Date, stays: [ItineraryStay]) -> ItineraryPlaceGuess? {
        guard !stays.isEmpty else { return nil }
        if let stay = stays.first(where: { $0.contains(date, pad: stayPad) }) {
            return ItineraryPlaceGuess(
                point: stay.point(at: date),
                relation: .insideStay,
                previous: stays.last(where: { $0.end <= stay.start && $0.start < stay.start }),
                next: stays.first(where: { $0.start >= stay.end && $0.start > stay.start }),
                editedFromID: nil
            )
        }
        let previous = stays.last { $0.end <= date }
        let next = stays.first { $0.start >= date }
        let previousGap = previous.map { date.timeIntervalSince($0.end) }
        let nextGap = next.map { $0.start.timeIntervalSince(date) }
        let usePrevious: Bool
        switch (previousGap, nextGap) {
        case let (prev?, next?):
            usePrevious = prev <= next
        case (_?, nil):
            usePrevious = true
        case (nil, _?):
            usePrevious = false
        default:
            return nil
        }
        guard let chosen = usePrevious ? previous : next else { return nil }
        return ItineraryPlaceGuess(
            point: chosen.point(at: date),
            relation: usePrevious ? .previousStay : .nextStay,
            previous: previous,
            next: next,
            editedFromID: nil
        )
    }

    static func shootingTimeZone(from members: [Footage]) -> TimeZone {
        var counts: [Int: Int] = [:]
        for item in members where item.captureMetadata.hasGPS && item.capturedAtHasTimeZone {
            guard let utc = item.capturedAt,
                  let local = item.capturedAtLocal,
                  let civil = parseCivil(local, timeZone: TimeZone(secondsFromGMT: 0)!)
            else { continue }
            let seconds = Int((civil.timeIntervalSince(utc) / 900).rounded()) * 900
            guard abs(seconds) <= 14 * 3600 else { continue }
            counts[seconds, default: 0] += 1
        }
        if let best = counts.max(by: { $0.value < $1.value })?.key,
           let zone = TimeZone(secondsFromGMT: best) {
            return zone
        }
        if let longitude = members.first(where: { $0.captureMetadata.hasGPS })?.longitude {
            let hours = Int((longitude / 15.0).rounded())
            return TimeZone(secondsFromGMT: hours * 3600) ?? .gmt
        }
        return TimeZone(secondsFromGMT: 0) ?? .gmt
    }

    static func alignedInstant(
        of footage: Footage,
        zone: TimeZone,
        offsets: [String: FolderTimeOffset]
    ) -> Date? {
        let raw: Date?
        if footage.capturedAtHasTimeZone {
            raw = footage.capturedAt
        } else if let local = footage.capturedAtLocal, let parsed = parseCivil(local, in: zone) {
            raw = parsed
        } else {
            raw = footage.capturedAt
        }
        guard let raw else { return nil }
        return GPXMatcher.adjustedCapture(
            raw,
            folder: GPXMatcher.folder(of: footage.relativePath),
            offsets: offsets
        )
    }

    static func parseCivil(_ raw: String, in timeZone: TimeZone) -> Date? {
        parseCivil(raw, timeZone: timeZone)
    }

    static func clusterStays(_ points: [GPXPoint]) -> [ItineraryStay] {
        var stays: [ItineraryStay] = []
        var current: [GPXPoint] = []
        func flush() {
            guard let stay = stay(from: current) else { return }
            if let last = stays.last,
               ItineraryRoute.distanceMeters(
                    from: (last.latitude, last.longitude),
                    to: (stay.latitude, stay.longitude)
               ) <= stayRadiusMeters,
               stay.start.timeIntervalSince(last.end) <= 45 * 60 {
                stays[stays.count - 1] = ItineraryStay(
                    start: last.start,
                    end: max(last.end, stay.end),
                    latitude: (last.latitude + stay.latitude) / 2,
                    longitude: (last.longitude + stay.longitude) / 2,
                    altitude: stay.altitude ?? last.altitude
                )
            } else {
                stays.append(stay)
            }
            current = []
        }
        for point in points {
            guard let last = current.last else {
                current = [point]
                continue
            }
            let centroidLatitude = current.map(\.latitude).reduce(0, +) / Double(current.count)
            let centroidLongitude = current.map(\.longitude).reduce(0, +) / Double(current.count)
            let fromCentroid = ItineraryRoute.distanceMeters(
                from: (centroidLatitude, centroidLongitude),
                to: (point.latitude, point.longitude)
            )
            let fromLast = ItineraryRoute.distanceMeters(
                from: (last.latitude, last.longitude),
                to: (point.latitude, point.longitude)
            )
            if fromCentroid <= stayRadiusMeters || fromLast <= stayRadiusMeters {
                current.append(point)
            } else {
                flush()
                current = [point]
            }
        }
        flush()
        return stays
    }

    private static func gpsAnchors(
        from members: [Footage],
        offsets: [String: FolderTimeOffset]
    ) -> [GPXPoint] {
        let zone = shootingTimeZone(from: members)
        return members.compactMap { item -> GPXPoint? in
            guard isReliableGPSAnchor(item) else { return nil }
            guard let latitude = item.latitude, let longitude = item.longitude else { return nil }
            guard let time = alignedInstant(of: item, zone: zone, offsets: offsets) else { return nil }
            return GPXPoint(time: time, latitude: latitude, longitude: longitude, altitude: item.altitude)
        }
        .sorted { $0.time < $1.time }
    }

    private static func stay(from points: [GPXPoint]) -> ItineraryStay? {
        guard let first = points.first, let last = points.last else { return nil }
        return ItineraryStay(
            start: first.time,
            end: last.time,
            latitude: median(points.map(\.latitude)),
            longitude: median(points.map(\.longitude)),
            altitude: medianOptional(points.compactMap(\.altitude))
        )
    }

    static func editedOriginal(
        for footage: Footage,
        in members: [Footage],
        zone: TimeZone,
        offsets: [String: FolderTimeOffset]
    ) -> (id: UUID, point: GPXPoint)? {
        guard !footage.captureMetadata.hasGPS else { return nil }
        guard footage.mediaKind == .image else { return nil }
        guard let hash = footage.phash, !hash.isEmpty else { return nil }
        guard let later = alignedInstant(of: footage, zone: zone, offsets: offsets) else { return nil }
        var best: (id: UUID, point: GPXPoint, distance: Int)?
        for other in members {
            guard other.id != footage.id else { continue }
            guard other.mediaKind == .image else { continue }
            guard isReliableGPSAnchor(other) else { continue }
            guard let otherHash = other.phash, !otherHash.isEmpty else { continue }
            guard let earlier = alignedInstant(of: other, zone: zone, offsets: offsets) else { continue }
            let lag = later.timeIntervalSince(earlier)
            guard lag >= editedMinLag else { continue }
            let distance = SearchService.hamming(hash, otherHash)
            guard distance <= editedPhashMaxDistance else { continue }
            guard let latitude = other.latitude, let longitude = other.longitude else { continue }
            if let current = best {
                if distance > current.distance { continue }
                if distance == current.distance, earlier <= current.point.time { continue }
            }
            best = (
                other.id,
                GPXPoint(time: earlier, latitude: latitude, longitude: longitude, altitude: other.altitude),
                distance
            )
        }
        guard let best else { return nil }
        return (best.id, best.point)
    }

    private static func parseCivil(_ raw: String, timeZone: TimeZone) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        if let date = formatter.date(from: trimmed) { return date }
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = formatter.date(from: trimmed) { return date }
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return formatter.date(from: trimmed)
    }

    private static func medianOptional(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return median(values)
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }
}
