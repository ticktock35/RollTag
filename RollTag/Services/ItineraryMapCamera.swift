import CoreGraphics
import Foundation

struct FittedMapRegion: Equatable, Sendable {
    var latitude: Double
    var longitude: Double
    var latitudeDelta: Double
    var longitudeDelta: Double

    var isUsable: Bool {
        latitude.isFinite && longitude.isFinite
            && latitudeDelta.isFinite && longitudeDelta.isFinite
            && latitude >= -90 && latitude <= 90
            && longitude >= -180 && longitude <= 180
            && latitudeDelta > 0 && longitudeDelta > 0
            && latitudeDelta < 120 && longitudeDelta < 180
    }

    func isPlausible(forContent fit: FittedMapRegion?) -> Bool {
        guard isUsable else { return false }
        guard let fit, fit.isUsable else { return true }
        if latitudeDelta > 40, fit.latitudeDelta < 8 { return false }
        if longitudeDelta > 40, fit.longitudeDelta < 8 { return false }
        return true
    }
}

enum ItineraryMapCamera {
    static let padding: Double = 1.45
    static let minDelta: Double = 0.0025
    static let singleFocusDelta: Double = 0.007
    /// 大約 1.3 公里。比這更近就拆開數字，改成一張一顆。
    static let clusterLatitudeDelta: Double = 0.012
    /// 同一家店 GPS 幾乎重疊時，當成一疊要攤開。
    static let stackMeters: Double = 18

    static func clustersPins(latitudeDelta: Double) -> Bool {
        latitudeDelta >= clusterLatitudeDelta
    }

    static func spreadOffsets(count: Int) -> [CGPoint] {
        guard count > 1 else { return [.zero] }
        let radius = 24 + CGFloat(count) * 3.2
        return (0..<count).map { index in
            let angle = (Double(index) / Double(count)) * 2 * Double.pi - Double.pi / 2
            return CGPoint(x: CGFloat(cos(angle)) * radius, y: CGFloat(sin(angle)) * radius)
        }
    }

    static func region(fitting points: [(latitude: Double, longitude: Double)]) -> FittedMapRegion? {
        guard let first = points.first else { return nil }
        var minLat = first.latitude
        var maxLat = first.latitude
        var minLon = first.longitude
        var maxLon = first.longitude
        for point in points.dropFirst() {
            minLat = min(minLat, point.latitude)
            maxLat = max(maxLat, point.latitude)
            minLon = min(minLon, point.longitude)
            maxLon = max(maxLon, point.longitude)
        }
        let latSpan = maxLat - minLat
        let lonSpan = maxLon - minLon
        if points.count == 1 || (latSpan < 1e-7 && lonSpan < 1e-7) {
            return region(focusing: first)
        }
        return FittedMapRegion(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2,
            latitudeDelta: max(latSpan * padding, minDelta),
            longitudeDelta: max(lonSpan * padding, minDelta)
        )
    }

    static func region(focusing point: (latitude: Double, longitude: Double)) -> FittedMapRegion {
        FittedMapRegion(
            latitude: point.latitude,
            longitude: point.longitude,
            latitudeDelta: singleFocusDelta,
            longitudeDelta: singleFocusDelta
        )
    }
}
