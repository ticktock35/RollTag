import AVFoundation
import CoreGraphics
import Foundation
import ImageIO

struct MediaMetadataSnapshot: Equatable {
    var latitude: Double?
    var longitude: Double?
    var altitude: Double?
    var capturedAt: Date?
}

enum MediaMetadata {
    static func read(url: URL) async -> MediaMetadataSnapshot {
        switch MediaKind.of(filename: url.lastPathComponent) {
        case .image:
            return readImage(url: url)
        case .video, .audio:
            return await readAVAsset(url: url)
        }
    }

    static func parseISO6709(_ raw: String) -> (latitude: Double, longitude: Double, altitude: Double?)? {
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let pattern = #"^([+-]\d+(?:\.\d+)?)([+-]\d+(?:\.\d+)?)(?:([+-]\d+(?:\.\d+)?))?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              match.numberOfRanges >= 3,
              let latRange = Range(match.range(at: 1), in: trimmed),
              let lonRange = Range(match.range(at: 2), in: trimmed),
              let latitude = Double(trimmed[latRange]),
              let longitude = Double(trimmed[lonRange])
        else { return nil }
        var altitude: Double?
        if match.numberOfRanges > 3, let altRange = Range(match.range(at: 3), in: trimmed) {
            altitude = Double(trimmed[altRange])
        }
        return (latitude, longitude, altitude)
    }

    static func signedCoordinate(_ value: Double, reference: String?, southOrWest: String) -> Double {
        let ref = (reference ?? "").uppercased()
        return ref == southOrWest ? -abs(value) : abs(value)
    }

    private static func readImage(url: URL) -> MediaMetadataSnapshot {
        var snapshot = MediaMetadataSnapshot()
        if let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            snapshot.capturedAt = ThumbnailService.exifDate(from: properties)
            if let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
               let lat = doubleValue(gps[kCGImagePropertyGPSLatitude]),
               let lon = doubleValue(gps[kCGImagePropertyGPSLongitude]) {
                snapshot.latitude = signedCoordinate(lat, reference: gps[kCGImagePropertyGPSLatitudeRef] as? String, southOrWest: "S")
                snapshot.longitude = signedCoordinate(lon, reference: gps[kCGImagePropertyGPSLongitudeRef] as? String, southOrWest: "W")
                snapshot.altitude = doubleValue(gps[kCGImagePropertyGPSAltitude])
            }
        }
        if snapshot.capturedAt == nil {
            snapshot.capturedAt = fileDate(url)
        }
        return snapshot
    }

    private static func readAVAsset(url: URL) async -> MediaMetadataSnapshot {
        var snapshot = MediaMetadataSnapshot()
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
        let items = (try? await asset.load(.metadata)) ?? []
        for item in items {
            if item.identifier == .quickTimeMetadataLocationISO6709
                || item.identifier == .commonIdentifierLocation,
               let text = try? await item.load(.stringValue),
               let gps = parseISO6709(text) {
                snapshot.latitude = gps.latitude
                snapshot.longitude = gps.longitude
                snapshot.altitude = gps.altitude
            }
            if snapshot.capturedAt == nil,
               item.identifier == .quickTimeMetadataCreationDate
                || item.identifier == .commonIdentifierCreationDate {
                if let date = try? await item.load(.dateValue) {
                    snapshot.capturedAt = date
                } else if let date = parseMetadataDate(try? await item.load(.stringValue)) {
                    snapshot.capturedAt = date
                }
            }
        }
        if snapshot.capturedAt == nil {
            snapshot.capturedAt = fileDate(url)
        }
        return snapshot
    }

    private static func parseMetadataDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: raw) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: raw)
    }

    private static func fileDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey]))?.creationDate
            ?? (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: return number.doubleValue
        case let number as Double: return number
        case let number as Int: return Double(number)
        case let text as String: return Double(text)
        default: return nil
        }
    }
}
