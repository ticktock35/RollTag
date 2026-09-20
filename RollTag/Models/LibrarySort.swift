import Foundation

enum LibrarySort: String, CaseIterable, Identifiable, Sendable {
    case relevance
    case filename
    case capturedAt
    case modified
    case duration
    case size
    case kind

    var id: String { rawValue }

    var localizationKey: String { "sort.\(rawValue)" }

    var defaultAscending: Bool {
        switch self {
        case .filename, .kind:
            return true
        case .relevance, .capturedAt, .modified, .duration, .size:
            return false
        }
    }
}
