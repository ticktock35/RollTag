import Foundation

struct GPXPoint: Equatable, Hashable, Sendable {
    var time: Date
    var latitude: Double
    var longitude: Double
    var altitude: Double?
}

struct GPXTrack: Equatable, Hashable, Sendable {
    var points: [GPXPoint]

    var start: Date? { points.first?.time }
    var end: Date? { points.last?.time }

    func location(at date: Date) -> GPXPoint? {
        guard !points.isEmpty else { return nil }
        if date < points[0].time || date > points[points.count - 1].time {
            return nil
        }
        var low = 0
        var high = points.count - 1
        while low < high {
            let mid = (low + high) / 2
            if points[mid].time < date {
                low = mid + 1
            } else {
                high = mid
            }
        }
        if low == 0 {
            return points[0]
        }
        let after = points[low]
        if after.time == date {
            return after
        }
        let before = points[low - 1]
        let span = after.time.timeIntervalSince(before.time)
        guard span > 0 else { return after }
        let t = date.timeIntervalSince(before.time) / span
        return GPXPoint(
            time: date,
            latitude: Self.lerp(before.latitude, after.latitude, t),
            longitude: Self.lerp(before.longitude, after.longitude, t),
            altitude: lerpAltitude(before.altitude, after.altitude, t)
        )
    }

    private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    private func lerpAltitude(_ a: Double?, _ b: Double?, _ t: Double) -> Double? {
        switch (a, b) {
        case let (first?, second?):
            return Self.lerp(first, second, t)
        case let (first?, nil):
            return first
        case let (nil, second?):
            return second
        default:
            return nil
        }
    }
}

enum GPXParseError: Error, Equatable {
    case empty
    case invalidXML
}

enum GPXDocument {
    static func parse(data: Data) throws -> GPXTrack {
        let parser = XMLParser(data: data)
        let delegate = GPXParserDelegate()
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true
        guard parser.parse() else {
            throw GPXParseError.invalidXML
        }
        let sorted = delegate.points.sorted { $0.time < $1.time }
        guard !sorted.isEmpty else { throw GPXParseError.empty }
        return GPXTrack(points: sorted)
    }

    static func parseGPXTime(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: trimmed) { return date }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: trimmed)
    }
}

private final class GPXParserDelegate: NSObject, XMLParserDelegate {
    var points: [GPXPoint] = []
    private var latitude: Double?
    private var longitude: Double?
    private var altitude: Double?
    private var time: Date?
    private var inPoint = false
    private var text = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = elementName.lowercased()
        if name == "trkpt" || name == "wpt" {
            inPoint = true
            latitude = Double(attributeDict["lat"] ?? "")
            longitude = Double(attributeDict["lon"] ?? "")
            altitude = nil
            time = nil
        }
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inPoint else { return }
        text += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = elementName.lowercased()
        if inPoint {
            if name == "time" {
                time = GPXDocument.parseGPXTime(text)
            } else if name == "ele" {
                altitude = Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
            } else if name == "trkpt" || name == "wpt" {
                if let time, let latitude, let longitude {
                    points.append(
                        GPXPoint(time: time, latitude: latitude, longitude: longitude, altitude: altitude)
                    )
                }
                inPoint = false
            }
        }
        text = ""
    }
}

struct GPXEligibleFile: Equatable, Sendable, Identifiable {
    var id: UUID
    var relativePath: String
    var filename: String
    var folder: String
    var capturedAt: Date
}

struct GPXCandidate: Equatable, Sendable, Identifiable {
    var id: UUID
    var relativePath: String
    var filename: String
    var folder: String
    var capturedAt: Date
    var adjustedAt: Date
    var latitude: Double
    var longitude: Double
    var altitude: Double?
}

enum GPXMatcher {
    static func folder(of relativePath: String) -> String {
        let dir = (relativePath as NSString).deletingLastPathComponent
        if dir.isEmpty || dir == "." { return "" }
        return dir
    }

    static func parentFolder(_ path: String) -> String {
        let dir = WarehouseFolderTree.normalize(path)
        if dir.isEmpty { return "" }
        let parent = (dir as NSString).deletingLastPathComponent
        if parent.isEmpty || parent == "." || parent == dir { return "" }
        return WarehouseFolderTree.normalize(parent)
    }

    /// More specific child folders win over a parent assignment.
    static func assignedTrack(directoryPath: String, assignments: [String: String]) -> String? {
        var current = WarehouseFolderTree.normalize(directoryPath)
        while true {
            if let name = assignments[current] { return name }
            if current.isEmpty { return nil }
            current = parentFolder(current)
        }
    }

    static func belongs(
        footage: Footage,
        filename: String,
        track: GPXTrack,
        assignments: [String: String],
        offsets: [String: Int]
    ) -> Bool {
        guard footage.status == .available else { return false }
        guard footage.mediaKind == .image || footage.mediaKind == .video else { return false }
        guard assignedTrack(directoryPath: footage.directoryPath, assignments: assignments) == filename else {
            return false
        }
        guard let capturedAt = footage.capturedAt else { return false }
        let minutes = offsets[folder(of: footage.relativePath)] ?? 0
        let adjusted = capturedAt.addingTimeInterval(TimeInterval(minutes * 60))
        return track.location(at: adjusted) != nil
    }

    static func shouldWriteGPS(_ capture: MediaMetadataSnapshot) -> Bool {
        !capture.hasGPS || capture.gpsSource == .gpx
    }

    static func eligible(from footage: [Footage]) -> [GPXEligibleFile] {
        footage.compactMap { item in
            guard item.status == .available else { return nil }
            guard item.mediaKind == .image || item.mediaKind == .video else { return nil }
            guard !item.captureMetadata.hasGPS else { return nil }
            guard let capturedAt = item.capturedAt else { return nil }
            return GPXEligibleFile(
                id: item.id,
                relativePath: item.relativePath,
                filename: item.filename,
                folder: folder(of: item.relativePath),
                capturedAt: capturedAt
            )
        }
    }

    static func candidates(
        files: [GPXEligibleFile],
        track: GPXTrack,
        offsets: [String: Int]
    ) -> [GPXCandidate] {
        files.compactMap { file in
            let minutes = offsets[file.folder] ?? 0
            let adjusted = file.capturedAt.addingTimeInterval(TimeInterval(minutes * 60))
            guard let point = track.location(at: adjusted) else { return nil }
            return GPXCandidate(
                id: file.id,
                relativePath: file.relativePath,
                filename: file.filename,
                folder: file.folder,
                capturedAt: file.capturedAt,
                adjustedAt: adjusted,
                latitude: point.latitude,
                longitude: point.longitude,
                altitude: point.altitude
            )
        }
    }
}

enum GPXOffsetStore {
    static let presets = [0, 1, -1, 5, -5, 15, -15, 30, -30, 60, -60]

    static func load(root: URL) -> [String: Int] {
        let url = offsetsURL(root: root)
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        var result: [String: Int] = [:]
        for (key, value) in object {
            if let number = value as? Int {
                result[key] = number
            } else if let number = value as? NSNumber {
                result[key] = number.intValue
            }
        }
        return result
    }

    static func save(_ offsets: [String: Int], root: URL) throws {
        let url = offsetsURL(root: root)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: offsets, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    static func copyTrack(from source: URL, root: URL) throws -> URL {
        let folder = root
            .appendingPathComponent(MediaConstants.rolltagDirectory)
            .appendingPathComponent(MediaConstants.gpxDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var destination = folder.appendingPathComponent(source.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) {
            let stamp = Int(Date().timeIntervalSince1970)
            let name = source.deletingPathExtension().lastPathComponent + "-\(stamp).gpx"
            destination = folder.appendingPathComponent(name)
        }
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    private static func offsetsURL(root: URL) -> URL {
        root
            .appendingPathComponent(MediaConstants.rolltagDirectory)
            .appendingPathComponent(MediaConstants.gpxOffsetsName)
    }
}

enum GPXAssignmentStore {
    static func load(root: URL) -> [String: String] {
        let url = assignmentsURL(root: root)
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return [:] }
        var result: [String: String] = [:]
        for (key, value) in object where !value.isEmpty {
            result[WarehouseFolderTree.normalize(key)] = value
        }
        return result
    }

    static func save(_ assignments: [String: String], root: URL) throws {
        let url = assignmentsURL(root: root)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: assignments, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    private static func assignmentsURL(root: URL) -> URL {
        root
            .appendingPathComponent(MediaConstants.rolltagDirectory)
            .appendingPathComponent(MediaConstants.gpxAssignmentsName)
    }
}

struct ImportedGPXTrack: Identifiable, Equatable, Hashable, Sendable {
    var filename: String
    var track: GPXTrack

    var id: String { filename }

    var displayName: String {
        (filename as NSString).deletingPathExtension
    }
}

struct WarehouseGPXState: Equatable, Hashable, Sendable {
    var tracks: [ImportedGPXTrack]
    var assignments: [String: String]
    var offsets: [String: Int]

    static let empty = WarehouseGPXState(tracks: [], assignments: [:], offsets: [:])

    func track(named filename: String) -> ImportedGPXTrack? {
        tracks.first { $0.filename == filename }
    }
}

enum GPXLibrary {
    static func load(root: URL) -> WarehouseGPXState {
        WarehouseGPXState(
            tracks: loadTracks(root: root),
            assignments: GPXAssignmentStore.load(root: root),
            offsets: GPXOffsetStore.load(root: root)
        )
    }

    static func loadTracks(root: URL) -> [ImportedGPXTrack] {
        let folder = root
            .appendingPathComponent(MediaConstants.rolltagDirectory)
            .appendingPathComponent(MediaConstants.gpxDirectory)
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls
            .filter { $0.pathExtension.lowercased() == "gpx" }
            .compactMap { url -> ImportedGPXTrack? in
                guard let data = try? Data(contentsOf: url),
                      let track = try? GPXDocument.parse(data: data)
                else { return nil }
                return ImportedGPXTrack(filename: url.lastPathComponent, track: track)
            }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }
}
