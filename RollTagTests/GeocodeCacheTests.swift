import XCTest
@testable import RollTag

final class GeocodeCacheTests: XCTestCase {
    func testNearbyCoordinatesReuseCachedLabel() {
        var cache = GeocodeCache()
        cache.remember(latitude: 1.3700, longitude: 103.8600, label: "Johor Bahru, Johor, Malaysia")
        XCTAssertEqual(cache.label(near: 1.3720, longitude: 103.8620), "Johor Bahru, Johor, Malaysia")
        XCTAssertNil(cache.label(near: 1.4200, longitude: 103.9200))
    }

    func testHalfKilometerIsInsideCacheRadius() {
        let meters = GeocodeCache.distanceMeters(
            fromLatitude: 1.3700,
            fromLongitude: 103.8600,
            toLatitude: 1.3730,
            toLongitude: 103.8630
        )
        XCTAssertLessThan(meters, GeocodeCache.matchRadiusMeters)
        XCTAssertGreaterThan(meters, 300)
    }

    func testPlaceLabelSkipsStreetAddressName() {
        let streetOnly = PlaceLabel.make(
            name: "12 Orchard Road",
            thoroughfare: "Orchard Road",
            locality: "Singapore",
            country: "Singapore"
        )
        XCTAssertEqual(streetOnly, "Singapore")

        let poi = PlaceLabel.make(
            areaOfInterest: "Club Med Ria Bintan",
            name: "Jalan Club Med",
            thoroughfare: "Jalan Club Med",
            locality: "Bintan",
            administrativeArea: "Riau Islands",
            country: "Indonesia"
        )
        XCTAssertEqual(poi, "Club Med Ria Bintan, Bintan, Riau Islands, Indonesia")
    }
}
