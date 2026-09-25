import CoreLocation
import Foundation

@MainActor
final class PlaceNameLookup {
    private let geocoder = CLGeocoder()
    private let cacheURL: URL
    private var cache: GeocodeCache

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        cacheURL = homeDirectory.appendingPathComponent("rolltag/geocode-cache.json")
        cache = Self.load(from: cacheURL)
    }

    func placeName(latitude: Double, longitude: Double) async -> String? {
        if let cached = cache.label(near: latitude, longitude: longitude) {
            return cached
        }
        guard let label = await reverse(latitude: latitude, longitude: longitude) else {
            return nil
        }
        cache.remember(latitude: latitude, longitude: longitude, label: label)
        save()
        return label
    }

    private func reverse(latitude: Double, longitude: Double) async -> String? {
        if geocoder.isGeocoding {
            geocoder.cancelGeocode()
        }
        let location = CLLocation(latitude: latitude, longitude: longitude)
        do {
            let marks = try await geocoder.reverseGeocodeLocation(location)
            return marks.compactMap(label(from:)).first
        } catch {
            return nil
        }
    }

    private func label(from mark: CLPlacemark) -> String? {
        PlaceLabel.make(
            areaOfInterest: mark.areasOfInterest?.first,
            name: mark.name,
            thoroughfare: mark.thoroughfare,
            subLocality: mark.subLocality,
            locality: mark.locality,
            administrativeArea: mark.administrativeArea,
            country: mark.country,
            ocean: mark.ocean
        )
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(cache).write(to: cacheURL, options: .atomic)
        } catch {
            return
        }
    }

    private static func load(from url: URL) -> GeocodeCache {
        guard let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(GeocodeCache.self, from: data)
        else {
            return GeocodeCache()
        }
        return cache
    }
}
