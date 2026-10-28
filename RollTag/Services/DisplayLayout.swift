import AppKit
import CoreGraphics
import Foundation

enum DisplayLayout {
    struct Screen: Identifiable, Hashable {
        var id: UInt32
        var name: String
        var frame: CGRect
        var visibleFrame: CGRect
        var isBuiltIn: Bool
    }

    static func screens(from nsScreens: [NSScreen] = NSScreen.screens) -> [Screen] {
        nsScreens.map { screen in
            let id = displayID(of: screen)
            return Screen(
                id: id,
                name: screen.localizedName,
                frame: screen.frame,
                visibleFrame: screen.visibleFrame,
                isBuiltIn: CGDisplayIsBuiltin(id) != 0
            )
        }
        .sorted { lhs, rhs in
            if lhs.isBuiltIn != rhs.isBuiltIn { return lhs.isBuiltIn && !rhs.isBuiltIn }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    static func displayID(of screen: NSScreen) -> UInt32 {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    static func screen(id: UInt32?, in screens: [Screen]) -> Screen? {
        guard let id else { return nil }
        return screens.first(where: { $0.id == id })
    }

    static func counterpart(to id: UInt32?, in screens: [Screen]) -> Screen? {
        guard screens.count > 1 else { return nil }
        if let id, let other = screens.first(where: { $0.id != id }) {
            return other
        }
        return screens.last
    }

    static func defaultPrimaryID(libraryScreenID: UInt32?, screens: [Screen]) -> UInt32? {
        guard screens.count > 1 else { return screens.first?.id }
        if let libraryScreenID, let other = counterpart(to: libraryScreenID, in: screens) {
            return other.id
        }
        return screens.first(where: { !$0.isBuiltIn })?.id ?? screens.last?.id
    }

    static func nsScreen(id: UInt32) -> NSScreen? {
        NSScreen.screens.first { displayID(of: $0) == id }
    }

    static func taggedWindow(_ id: String) -> NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == id }
    }
}
