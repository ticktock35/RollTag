import Foundation

enum FootageStatus: String, Codable, Equatable, Sendable {
    case available
    case missing
}

struct TagAssignment: Codable, Hashable, Identifiable, Sendable {
    var category: String
    var value: String
    var source: String

    var id: String { "\(category)/\(value)/\(source)" }
    var identityKey: String { "\(category)/\(value)" }

    static let customCategory = "custom"

    var isCustom: Bool { category == Self.customCategory }

    static func user(category: String, value: String) -> TagAssignment {
        TagAssignment(category: category, value: value, source: "user")
    }

    static func ai(category: String, value: String) -> TagAssignment {
        TagAssignment(category: category, value: value, source: "ai")
    }

    static func path(category: String, value: String) -> TagAssignment {
        TagAssignment(category: category, value: value, source: "path")
    }

    static func sourceRank(_ source: String) -> Int {
        switch source {
        case "user": return 0
        case "path": return 1
        case "ai": return 2
        default: return 3
        }
    }

    static func custom(_ raw: String) -> TagAssignment? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        return user(category: customCategory, value: value)
    }

    static func customs(from raw: String) -> [TagAssignment] {
        raw
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: "；", with: ",")
            .replacingOccurrences(of: ";", with: ",")
            .split(separator: ",")
            .compactMap { custom(String($0)) }
    }

    /// Same category + value is one tag, even if `user` and `ai` both exist.
    static func uniqued(_ tags: [TagAssignment]) -> [TagAssignment] {
        var best: [String: TagAssignment] = [:]
        var order: [String] = []
        for tag in tags {
            let key = tag.identityKey
            if let existing = best[key] {
                if sourceRank(tag.source) < sourceRank(existing.source) {
                    best[key] = tag
                }
            } else {
                best[key] = tag
                order.append(key)
            }
        }
        return order.map { best[$0]! }
    }
}

struct Footage: Identifiable, Hashable {
    var id: UUID
    var warehouseID: UUID
    var relativePath: String
    var filename: String
    var size: Int64
    var mtime: Int64
    var contentHash: String?
    var phash: String?
    var status: FootageStatus
    var duration: Double?
    var width: Int?
    var height: Int?
    var createdAt: Date
    var updatedAt: Date
    var parentID: UUID?
    var userNotes: String
    var tags: [TagAssignment]
    var capturedAt: Date? = nil
    var capturedAtLocal: String? = nil
    var capturedAtHasTimeZone: Bool = false
    var capturedAtSource: CaptureTimeSource? = nil
    var latitude: Double? = nil
    var longitude: Double? = nil
    var altitude: Double? = nil

    var directoryPath: String {
        let dir = (relativePath as NSString).deletingLastPathComponent
        return dir == "." ? "" : dir
    }

    var isTrimmedClip: Bool { parentID != nil }

    var mediaKind: MediaKind { MediaKind.of(filename: filename) }

    var isTooSmallToPreview: Bool {
        mediaKind == .video && size < MediaConstants.minimumPlayableVideoBytes
    }

    var canAITag: Bool {
        status == .available && (mediaKind == .video || mediaKind == .image) && !isTooSmallToPreview
    }

    var captureMetadata: MediaMetadataSnapshot {
        get {
            MediaMetadataSnapshot(
                latitude: latitude,
                longitude: longitude,
                altitude: altitude,
                capturedAt: capturedAt,
                capturedAtLocal: capturedAtLocal,
                capturedAtHasTimeZone: capturedAtHasTimeZone,
                capturedAtSource: capturedAtSource
            )
        }
        set {
            latitude = newValue.latitude
            longitude = newValue.longitude
            altitude = newValue.altitude
            capturedAt = newValue.capturedAt
            capturedAtLocal = newValue.capturedAtLocal
            capturedAtHasTimeZone = newValue.capturedAtHasTimeZone
            capturedAtSource = newValue.capturedAtSource
        }
    }

    func absoluteURL(warehouseRoot: URL) -> URL {
        warehouseRoot.appendingPathComponent(relativePath)
    }
}

enum DuplicateResolution: String, Codable, Equatable {
    case unresolved
    case keepSeparate
    case merged
}

struct DuplicateGroup: Identifiable, Hashable {
    var id: UUID
    var contentHash: String
    var resolution: DuplicateResolution
    var memberIDs: [UUID]
}

struct ScoredFootage: Identifiable, Hashable {
    var footage: Footage
    var score: Double
    var warehouseName: String
    var warehousePath: String
    var isOnline: Bool

    var id: UUID { footage.id }
}
