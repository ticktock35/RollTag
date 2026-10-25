import Foundation

enum MediaPlaybackFailure: Equatable {
    case none
    case missing
    case incomplete
    case decode

    static func classify(exists: Bool, fileSize: Int64, kind: MediaKind, playerError: Error? = nil) -> MediaPlaybackFailure {
        if kind == .video, fileSize < MediaConstants.minimumPlayableVideoBytes {
            return .incomplete
        }
        if !exists || isMissingError(playerError) {
            return .missing
        }
        if playerError != nil {
            return .decode
        }
        return .none
    }

    static func isMissingError(_ error: Error?) -> Bool {
        guard let error else { return false }
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain, ns.code == NSFileReadNoSuchFileError { return true }
        if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorFileDoesNotExist { return true }
        if ns.domain == NSPOSIXErrorDomain, ns.code == Int(ENOENT) { return true }
        let text = (ns.localizedDescription + " " + (ns.localizedFailureReason ?? "")).lowercased()
        return text.contains("no such file")
            || text.contains("could not be opened") && text.contains("doesn’t exist")
            || text.contains("doesn't exist")
            || text.contains("找不到")
    }
}
