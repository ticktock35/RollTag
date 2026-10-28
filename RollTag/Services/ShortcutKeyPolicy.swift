import Foundation

enum ShortcutKeyWindow: Equatable, Sendable {
    case library
    case playerStage
    case settings
    case trim
    case sheet
    case other
}

enum ShortcutKeyPolicy {
    /// 媒體清單快捷鍵：單螢幕在媒體庫視窗；雙螢幕時播放視窗在最前也算。
    static func allowsLibraryCommands(window: ShortcutKeyWindow, isDualScreen: Bool) -> Bool {
        switch window {
        case .library:
            return true
        case .playerStage:
            return isDualScreen
        case .settings, .trim, .sheet, .other:
            return false
        }
    }

    static func allowsSelectAll(window: ShortcutKeyWindow, isDualScreen: Bool) -> Bool {
        allowsLibraryCommands(window: window, isDualScreen: isDualScreen)
    }

    static func allowsGridMove(
        window: ShortcutKeyWindow,
        isDualScreen: Bool,
        sidebarFocused: Bool,
        libraryGridFocused: Bool,
        isFullscreen: Bool,
        duplicatesActive: Bool,
        isDuplicatesCollection: Bool
    ) -> Bool {
        guard !duplicatesActive, !isFullscreen, !isDuplicatesCollection else { return false }
        guard allowsLibraryCommands(window: window, isDualScreen: isDualScreen) else { return false }
        if window == .library, sidebarFocused, !libraryGridFocused {
            return false
        }
        return true
    }

    static func allowsStepMedia(window: ShortcutKeyWindow, isFullscreen: Bool) -> Bool {
        guard !isFullscreen else { return false }
        switch window {
        case .library, .playerStage:
            return true
        default:
            return false
        }
    }

    static func allowsPlayback(window: ShortcutKeyWindow) -> Bool {
        switch window {
        case .library, .playerStage:
            return true
        default:
            return false
        }
    }
}
