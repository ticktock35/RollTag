import AVFoundation
import Foundation
import ImageIO

enum CaptureTimeSource: String, Codable, Equatable, Sendable {
    case header
    case djiFilename
    case fileDate
}

struct MediaMetadataSnapshot: Equatable, Sendable {
    var latitude: Double?
    var longitude: Double?
    var altitude: Double?
    var capturedAt: Date?
    var capturedAtLocal: String?
    var capturedAtHasTimeZone: Bool = false
    var capturedAtSource: CaptureTimeSource?

    var hasGPS: Bool { latitude != nil && longitude != nil }

    func capturedAtForAI() -> String? {
        if !capturedAtHasTimeZone, let capturedAtLocal, !capturedAtLocal.isEmpty {
            return capturedAtLocal
        }
        guard let capturedAt else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: capturedAt)
    }

    func inspectorTimeText() -> String? {
        if let capturedAtLocal, !capturedAtLocal.isEmpty, !capturedAtHasTimeZone {
            return capturedAtLocal.replacingOccurrences(of: "T", with: " ")
        }
        guard let capturedAt else { return nil }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: capturedAt)
    }
}

enum MediaMetadata {
    static let earliestPlausibleYear = 2015

    static func read(url: URL, skipImplausibleHeader: Bool = true) async -> MediaMetadataSnapshot {
        let header = await readHeader(url: url)
        var snapshot = MediaMetadataSnapshot(
            latitude: header.latitude,
            longitude: header.longitude,
            altitude: header.altitude
        )

        if let headerTime = header.time, !skipImplausibleHeader || isPlausible(headerTime) {
            apply(headerTime, source: .header, to: &snapshot)
            return snapshot
        }
        if let dji = parseDJIFilename(url.lastPathComponent), !skipImplausibleHeader || isPlausible(dji) {
            apply(dji, source: .djiFilename, to: &snapshot)
            return snapshot
        }
        if let file = fileClock(url) {
            apply(file, source: .fileDate, to: &snapshot)
        }
        return snapshot
    }

    static func parseDJIFilename(_ filename: String) -> CaptureClock? {
        guard filename.hasPrefix("DJI_"), filename.count >= 18 else { return nil }
        let digits = String(filename.dropFirst(4).prefix(14))
        guard digits.count == 14, digits.allSatisfy(\.isNumber) else { return nil }
        return clock(fromPacked: digits, hasTimeZone: false)
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

    static func isPlausible(_ clock: CaptureClock) -> Bool {
        guard let year = clock.year, year >= earliestPlausibleYear else { return false }
        guard let date = clock.date else { return false }
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return calendar.startOfDay(for: date) <= calendar.startOfDay(for: tomorrow)
    }

    struct CaptureClock: Equatable {
        var date: Date?
        var local: String?
        var hasTimeZone: Bool
        var year: Int?
    }

    private struct HeaderRead {
        var time: CaptureClock?
        var latitude: Double?
        var longitude: Double?
        var altitude: Double?
    }

    private static func apply(_ clock: CaptureClock, source: CaptureTimeSource, to snapshot: inout MediaMetadataSnapshot) {
        snapshot.capturedAt = clock.date
        snapshot.capturedAtLocal = clock.local
        snapshot.capturedAtHasTimeZone = clock.hasTimeZone
        snapshot.capturedAtSource = source
    }

    private static func readHeader(url: URL) async -> HeaderRead {
        switch MediaKind.of(filename: url.lastPathComponent) {
        case .image:
            return readImageHeader(url: url)
        case .video, .audio:
            return await readAVHeader(url: url)
        }
    }

    private static func readImageHeader(url: URL) -> HeaderRead {
        var header = HeaderRead()
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return header }

        header.time = exifClock(from: properties)
        if let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
           let lat = doubleValue(gps[kCGImagePropertyGPSLatitude]),
           let lon = doubleValue(gps[kCGImagePropertyGPSLongitude]) {
            header.latitude = signedCoordinate(lat, reference: gps[kCGImagePropertyGPSLatitudeRef] as? String, southOrWest: "S")
            header.longitude = signedCoordinate(lon, reference: gps[kCGImagePropertyGPSLongitudeRef] as? String, southOrWest: "W")
            if let altitude = doubleValue(gps[kCGImagePropertyGPSAltitude]) {
                let below = (gps[kCGImagePropertyGPSAltitudeRef] as? NSNumber)?.intValue == 1
                header.altitude = below ? -abs(altitude) : altitude
            }
        }
        return header
    }

    private static func readAVHeader(url: URL) async -> HeaderRead {
        var header = HeaderRead()
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
        let items = (try? await asset.load(.metadata)) ?? []
        for item in items {
            if item.identifier == .quickTimeMetadataLocationISO6709
                || item.identifier == .commonIdentifierLocation,
               let text = try? await item.load(.stringValue),
               let gps = parseISO6709(text) {
                header.latitude = gps.latitude
                header.longitude = gps.longitude
                header.altitude = gps.altitude
            }
            if header.time == nil,
               item.identifier == .quickTimeMetadataCreationDate
                || item.identifier == .commonIdentifierCreationDate {
                if let date = try? await item.load(.dateValue) {
                    header.time = clock(from: date, hasTimeZone: true)
                } else if let raw = try? await item.load(.stringValue) {
                    header.time = parseMetadataClock(raw)
                }
            }
        }
        return header
    }

    static func exifClock(from properties: [CFString: Any]) -> CaptureClock? {
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let raw = (exif?[kCGImagePropertyExifDateTimeOriginal] as? String)
            ?? (exif?[kCGImagePropertyExifDateTimeDigitized] as? String)
        guard let raw else { return nil }
        let offset = (exif?[kCGImagePropertyExifOffsetTimeOriginal] as? String)
            ?? (exif?[kCGImagePropertyExifOffsetTimeDigitized] as? String)
            ?? (exif?[kCGImagePropertyExifOffsetTime] as? String)
        return parseEXIFClock(raw, offset: offset)
    }

    static func parseEXIFClock(_ raw: String, offset: String?) -> CaptureClock? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let day = parts[0].split(separator: ":")
        let time = parts[1].split(separator: ":")
        guard day.count == 3, time.count >= 2,
              let year = Int(day[0]), let month = Int(day[1]), let dayValue = Int(day[2]),
              let hour = Int(time[0]), let minute = Int(time[1])
        else { return nil }
        let second = time.count > 2 ? Int(Double(time[2]) ?? 0) ?? 0 : 0
        let local = localString(year: year, month: month, day: dayValue, hour: hour, minute: minute, second: second)
        if let offset, let dated = dateWithOffset(year: year, month: month, day: dayValue, hour: hour, minute: minute, second: second, offset: offset) {
            return CaptureClock(date: dated, local: local, hasTimeZone: true, year: year)
        }
        return CaptureClock(
            date: gmtDate(year: year, month: month, day: dayValue, hour: hour, minute: minute, second: second),
            local: local,
            hasTimeZone: false,
            year: year
        )
    }

    static func parseMetadataClock(_ raw: String) -> CaptureClock? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: trimmed) {
            return clock(from: date, hasTimeZone: true)
        }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: trimmed) {
            return clock(from: date, hasTimeZone: true)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        if let date = formatter.date(from: trimmed) {
            return CaptureClock(date: date, local: String(trimmed.prefix(19)), hasTimeZone: false, year: year(of: date))
        }
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = formatter.date(from: trimmed) {
            return CaptureClock(
                date: date,
                local: trimmed.replacingOccurrences(of: " ", with: "T"),
                hasTimeZone: false,
                year: year(of: date)
            )
        }
        return nil
    }

    private static func clock(fromPacked digits: String, hasTimeZone: Bool) -> CaptureClock? {
        guard digits.count == 14,
              let year = Int(digits.prefix(4)),
              let month = Int(digits.dropFirst(4).prefix(2)),
              let day = Int(digits.dropFirst(6).prefix(2)),
              let hour = Int(digits.dropFirst(8).prefix(2)),
              let minute = Int(digits.dropFirst(10).prefix(2)),
              let second = Int(digits.suffix(2))
        else { return nil }
        return CaptureClock(
            date: gmtDate(year: year, month: month, day: day, hour: hour, minute: minute, second: second),
            local: localString(year: year, month: month, day: day, hour: hour, minute: minute, second: second),
            hasTimeZone: hasTimeZone,
            year: year
        )
    }

    private static func clock(from date: Date, hasTimeZone: Bool) -> CaptureClock {
        CaptureClock(date: date, local: nil, hasTimeZone: hasTimeZone, year: year(of: date))
    }

    private static func fileClock(_ url: URL) -> CaptureClock? {
        guard let date = fileDate(url) else { return nil }
        return clock(from: date, hasTimeZone: true)
    }

    private static func fileDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey]))?.creationDate
            ?? (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    private static func year(of date: Date) -> Int? {
        Calendar(identifier: .gregorian).dateComponents([.year], from: date).year
    }

    private static func localString(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int) -> String {
        String(format: "%04d-%02d-%02dT%02d:%02d:%02d", year, month, day, hour, minute, second)
    }

    private static func gmtDate(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))
    }

    private static func dateWithOffset(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        second: Int,
        offset: String
    ) -> Date? {
        let local = localString(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let trimmed = offset.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "Z" || trimmed == "z" {
            return iso.date(from: local + "Z")
        }
        let compact = trimmed.replacingOccurrences(of: ":", with: "")
        guard compact.count == 5, let sign = compact.first, sign == "+" || sign == "-" else {
            return gmtDate(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        }
        return iso.date(from: local + String(sign) + compact.dropFirst().prefix(2) + ":" + compact.suffix(2))
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
