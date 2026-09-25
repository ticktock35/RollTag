import Foundation

struct GeocodeCacheEntry: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    var label: String
}

struct GeocodeCache: Codable, Equatable {
    static let matchRadiusMeters = 1000.0
    static let maxEntries = 2000

    var entries: [GeocodeCacheEntry] = []

    func label(near latitude: Double, longitude: Double) -> String? {
        nearest(latitude: latitude, longitude: longitude)?.label
    }

    mutating func remember(latitude: Double, longitude: Double, label: String) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let index = nearestIndex(latitude: latitude, longitude: longitude) {
            entries[index].label = trimmed
            let hit = entries.remove(at: index)
            entries.insert(hit, at: 0)
            return
        }
        entries.insert(
            GeocodeCacheEntry(latitude: latitude, longitude: longitude, label: trimmed),
            at: 0
        )
        if entries.count > Self.maxEntries {
            entries = Array(entries.prefix(Self.maxEntries))
        }
    }

    static func distanceMeters(
        fromLatitude: Double,
        fromLongitude: Double,
        toLatitude: Double,
        toLongitude: Double
    ) -> Double {
        let earth = 6_371_000.0
        let lat1 = fromLatitude * .pi / 180
        let lat2 = toLatitude * .pi / 180
        let dLat = (toLatitude - fromLatitude) * .pi / 180
        let dLon = (toLongitude - fromLongitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return earth * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    private func nearest(latitude: Double, longitude: Double) -> GeocodeCacheEntry? {
        guard let index = nearestIndex(latitude: latitude, longitude: longitude) else { return nil }
        return entries[index]
    }

    private func nearestIndex(latitude: Double, longitude: Double) -> Int? {
        var bestIndex: Int?
        var bestDistance = Self.matchRadiusMeters
        for (index, entry) in entries.enumerated() {
            let distance = Self.distanceMeters(
                fromLatitude: latitude,
                fromLongitude: longitude,
                toLatitude: entry.latitude,
                toLongitude: entry.longitude
            )
            if distance <= bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }
}

enum PlaceLabel {
    static func make(
        areaOfInterest: String? = nil,
        name: String? = nil,
        thoroughfare: String? = nil,
        subLocality: String? = nil,
        locality: String? = nil,
        administrativeArea: String? = nil,
        country: String? = nil,
        ocean: String? = nil
    ) -> String? {
        var parts: [String] = []
        func append(_ raw: String?) {
            let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !value.isEmpty, !parts.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) else {
                return
            }
            parts.append(value)
        }

        append(areaOfInterest)
        if let name, shouldKeepName(name, thoroughfare: thoroughfare) {
            append(name)
        }
        append(subLocality)
        append(locality)
        append(administrativeArea)
        append(country)
        append(ocean)
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private static func shouldKeepName(_ name: String, thoroughfare: String?) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard let street = thoroughfare?.trimmingCharacters(in: .whitespacesAndNewlines), !street.isEmpty else {
            return true
        }
        if trimmed.caseInsensitiveCompare(street) == .orderedSame {
            return false
        }
        return !trimmed.localizedCaseInsensitiveContains(street)
    }
}
