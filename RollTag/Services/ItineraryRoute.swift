import Foundation

enum ItineraryRoute {
    static let nearbyMeters: Double = 50_000
    static let earthRadius: Double = 6_371_000
    /// 比民航機再快一點。短時間超過這個速度，當 GPS 亂跳。
    static let maxPlausibleSpeedMps: Double = 300
    static let burstInterval: TimeInterval = 0.75
    static let burstMaxMeters: Double = 2_000

    enum Kind: String, Equatable, Sendable {
        case land
        case sea
    }

    struct TimedPoint: Sendable {
        var latitude: Double
        var longitude: Double
        var time: Date?

        var coordinate: (latitude: Double, longitude: Double) {
            (latitude, longitude)
        }
    }

    struct Segment: Sendable {
        var kind: Kind
        var points: [(latitude: Double, longitude: Double)]
    }

    static func kind(
        from: (latitude: Double, longitude: Double),
        to: (latitude: Double, longitude: Double)
    ) -> Kind {
        if shareLandMass(from, to) { return .land }
        return distanceMeters(from: from, to: to) >= nearbyMeters ? .sea : .land
    }

    /// 丟掉中間那顆不合理的亂跳，前後合理的點仍留在同一條時間軸上。
    static func withoutSpikes(_ points: [TimedPoint]) -> [TimedPoint] {
        var kept: [TimedPoint] = []
        var index = 0
        while index < points.count {
            let point = points[index]
            guard let last = kept.last else {
                kept.append(point)
                index += 1
                continue
            }
            if isPlausibleHop(from: last, to: point) {
                kept.append(point)
                index += 1
                continue
            }
            let next = index + 1 < points.count ? points[index + 1] : nil
            if let next, isPlausibleHop(from: last, to: next) {
                index += 1
                continue
            }
            if kept.count == 1, let next, isPlausibleHop(from: point, to: next) {
                kept = [point]
                index += 1
                continue
            }
            kept.append(point)
            index += 1
        }
        return kept
    }

    static func isPlausibleHop(from: TimedPoint, to: TimedPoint) -> Bool {
        let distance = distanceMeters(from: from.coordinate, to: to.coordinate)
        guard distance.isFinite else { return false }
        if distance < 1 { return true }
        switch (from.time, to.time) {
        case let (start?, end?):
            let dt = abs(end.timeIntervalSince(start))
            if dt <= burstInterval {
                return distance <= burstMaxMeters
            }
            return distance / dt <= maxPlausibleSpeedMps
        default:
            return true
        }
    }

    static func segments(
        connecting points: [(latitude: Double, longitude: Double)]
    ) -> [Segment] {
        segments(connecting: points.map { TimedPoint(latitude: $0.latitude, longitude: $0.longitude, time: nil) })
    }

    static func segments(connecting points: [TimedPoint]) -> [Segment] {
        var result: [Segment] = []
        for run in plausibleRuns(points) {
            result.append(contentsOf: polylineSegments(for: run))
        }
        return result
    }

    static func coordinatesForFit(from points: [TimedPoint]) -> [(latitude: Double, longitude: Double)] {
        let kept = plausibleRuns(points).flatMap { $0 }.map(\.coordinate)
        if kept.isEmpty {
            return points.map(\.coordinate)
        }
        return kept
    }

    static func plausibleRuns(_ points: [TimedPoint]) -> [[TimedPoint]] {
        guard !points.isEmpty else { return [] }
        var runs: [[TimedPoint]] = []
        var current: [TimedPoint] = []
        var index = 0
        while index < points.count {
            let point = points[index]
            guard let last = current.last else {
                current = [point]
                index += 1
                continue
            }
            if isPlausibleHop(from: last, to: point) {
                current.append(point)
                index += 1
                continue
            }
            let next = index + 1 < points.count ? points[index + 1] : nil
            if let next, isPlausibleHop(from: last, to: next) {
                index += 1
                continue
            }
            if current.count == 1, let next, isPlausibleHop(from: point, to: next) {
                current = [point]
                index += 1
                continue
            }
            if current.count >= 2 {
                runs.append(current)
            }
            current = [point]
            index += 1
        }
        if current.count >= 2 {
            runs.append(current)
        } else if runs.isEmpty, current.count == 1 {
            runs.append(current)
        }
        return runs
    }

    private static func polylineSegments(for run: [TimedPoint]) -> [Segment] {
        guard run.count >= 2 else { return [] }
        var result: [Segment] = []
        var land: [(latitude: Double, longitude: Double)] = []
        func flushLand() {
            if land.count >= 2 {
                result.append(Segment(kind: .land, points: land))
            }
            land = []
        }
        for index in 0..<(run.count - 1) {
            let start = run[index].coordinate
            let end = run[index + 1].coordinate
            if abs(start.latitude - end.latitude) < 1e-8, abs(start.longitude - end.longitude) < 1e-8 {
                continue
            }
            switch kind(from: start, to: end) {
            case .land:
                if land.isEmpty { land.append(start) }
                land.append(end)
            case .sea:
                flushLand()
                result.append(Segment(kind: .sea, points: geodesic(from: start, to: end, samples: 24)))
            }
        }
        flushLand()
        return result
    }

    static func distanceMeters(
        from: (latitude: Double, longitude: Double),
        to: (latitude: Double, longitude: Double)
    ) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLat = (to.latitude - from.latitude) * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(max(0, 1 - a)))
        return earthRadius * c
    }

    static func geodesic(
        from: (latitude: Double, longitude: Double),
        to: (latitude: Double, longitude: Double),
        samples: Int
    ) -> [(latitude: Double, longitude: Double)] {
        let count = max(samples, 2)
        let start = vector(from)
        let end = vector(to)
        let dot = max(-1, min(1, start.x * end.x + start.y * end.y + start.z * end.z))
        let omega = acos(dot)
        if omega < 1e-8 {
            return [from, to]
        }
        var points: [(latitude: Double, longitude: Double)] = []
        for step in 0..<count {
            let t = Double(step) / Double(count - 1)
            let a = sin((1 - t) * omega) / sin(omega)
            let b = sin(t * omega) / sin(omega)
            points.append(
                coordinate(
                    x: a * start.x + b * end.x,
                    y: a * start.y + b * end.y,
                    z: a * start.z + b * end.z
                )
            )
        }
        return points
    }

    static func shareLandMass(
        _ from: (latitude: Double, longitude: Double),
        _ to: (latitude: Double, longitude: Double)
    ) -> Bool {
        let left = landMasses(containing: from)
        let right = landMasses(containing: to)
        return !left.isDisjoint(with: right)
    }

    static func landMasses(
        containing point: (latitude: Double, longitude: Double)
    ) -> Set<String> {
        let islands = islandMasses.filter { $0.contains(point) }.map(\.id)
        if !islands.isEmpty { return Set(islands) }
        return Set(continentMasses.filter { $0.contains(point) }.map(\.id))
    }

    private struct LandMass {
        var id: String
        var latitudes: ClosedRange<Double>
        var longitudes: ClosedRange<Double>

        func contains(_ point: (latitude: Double, longitude: Double)) -> Bool {
            latitudes.contains(point.latitude) && longitudes.contains(point.longitude)
        }
    }

    /// 島嶼先判，避免被歐亞／美洲大陸框吃進去。
    private static let islandMasses: [LandMass] = [
        LandMass(id: "taiwan", latitudes: 21.8...25.4, longitudes: 119.9...122.15),
        LandMass(id: "japan", latitudes: 24.0...45.8, longitudes: 122.9...146.0),
        LandMass(id: "philippines", latitudes: 4.5...21.2, longitudes: 116.8...126.7),
        LandMass(id: "indonesia", latitudes: -11.0 ... 6.1, longitudes: 95.0...141.0),
        LandMass(id: "sri-lanka", latitudes: 5.8...9.9, longitudes: 79.5...82.1),
        LandMass(id: "uk", latitudes: 49.8...58.7, longitudes: -8.7 ... 1.8),
        LandMass(id: "ireland", latitudes: 51.3...55.5, longitudes: -10.6 ... -5.4),
        LandMass(id: "iceland", latitudes: 63.2...66.6, longitudes: -24.6 ... -13.4),
        LandMass(id: "madagascar", latitudes: -25.7 ... -11.9, longitudes: 43.1...50.6),
        LandMass(id: "new-zealand", latitudes: -47.4 ... -34.3, longitudes: 166.3...178.6),
        LandMass(id: "hawaii", latitudes: 18.7...22.4, longitudes: -160.5 ... -154.6),
        LandMass(id: "hainan", latitudes: 18.1...20.2, longitudes: 108.6...111.1),
        LandMass(id: "tasmania", latitudes: -43.8 ... -40.4, longitudes: 144.5...148.5),
    ]

    private static let continentMasses: [LandMass] = [
        LandMass(id: "australia", latitudes: -39.2 ... -10.0, longitudes: 112.0...154.5),
        LandMass(id: "eurasia", latitudes: 1.2...72.0, longitudes: -10.0 ... 141.0),
        LandMass(id: "africa", latitudes: -35.0 ... 37.5, longitudes: -18.0 ... 52.0),
        LandMass(id: "north-america", latitudes: 14.5...72.0, longitudes: -168.0 ... -52.0),
        LandMass(id: "south-america", latitudes: -56.0 ... 12.5, longitudes: -82.0 ... -34.0),
    ]

    private static func vector(
        _ point: (latitude: Double, longitude: Double)
    ) -> (x: Double, y: Double, z: Double) {
        let lat = point.latitude * .pi / 180
        let lon = point.longitude * .pi / 180
        return (cos(lat) * cos(lon), cos(lat) * sin(lon), sin(lat))
    }

    private static func coordinate(x: Double, y: Double, z: Double) -> (latitude: Double, longitude: Double) {
        (
            latitude: atan2(z, sqrt(x * x + y * y)) * 180 / .pi,
            longitude: atan2(y, x) * 180 / .pi
        )
    }
}
