import Foundation

struct DiskEntry: Equatable, Sendable {
    var relativePath: String
    var size: Int64
    var mtime: Int64

    var filename: String {
        (relativePath as NSString).lastPathComponent
    }
}

struct FootageSnapshot: Equatable, Sendable {
    var id: UUID
    var relativePath: String
    var filename: String
    var size: Int64
    var mtime: Int64
    var contentHash: String?
    var phash: String?
    var status: FootageStatus
    var tags: [TagAssignment]
    var userNotes: String
    var parentID: UUID?
    var duration: Double?
    var width: Int?
    var height: Int?
    var capturedAt: Date?
    var needsReanalysis: Bool

    var directoryPath: String {
        let dir = (relativePath as NSString).deletingLastPathComponent
        return dir == "." ? "" : dir
    }
}

struct ReconcileOutcome: Equatable {
    var records: [FootageSnapshot]
    var hashedPaths: [String]
    var duplicateHashes: [String]
}

enum PreviewLayout {
    static let tallest: CGFloat = 0.55
    static let widest: CGFloat = 2.35
    static let videoFallback: CGFloat = 16 / 9

    static func aspect(width: Int?, height: Int?, fallback: CGFloat = videoFallback) -> CGFloat {
        guard let width, let height, width > 0, height > 0 else { return fallback }
        return min(max(CGFloat(width) / CGFloat(height), tallest), widest)
    }

    static func aspect(size: CGSize, fallback: CGFloat = videoFallback) -> CGFloat {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        return aspect(width: width, height: height, fallback: fallback)
    }
}

enum MediaKind: String, Equatable, Sendable {
    case video
    case image
    case audio

    var canHoverPlay: Bool { self != .image }
    var canTrim: Bool { self == .video }

    static func of(filename: String) -> MediaKind {
        let ext = (filename as NSString).pathExtension.lowercased()
        if MediaConstants.imageExtensions.contains(ext) { return .image }
        if MediaConstants.audioExtensions.contains(ext) { return .audio }
        return .video
    }
}

enum MediaConstants {
    static let videoExtensions: Set<String> = ["mov", "mp4", "m4v", "avi", "mkv", "mxf"]
    static let imageExtensions: Set<String> = ["heic", "heif", "jpg", "jpeg", "png", "webp", "gif"]
    static let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "wav"]
    static let supportedExtensions: Set<String> = videoExtensions.union(imageExtensions).union(audioExtensions)
    static let rolltagDirectory = ".rolltag"
    static let databaseName = "warehouse.sqlite"
    static let thumbsDirectory = "thumbs"
    static let trimmedDirectory = "trimmed"
    static let minimumPlayableVideoBytes: Int64 = 8 * 1024
}
