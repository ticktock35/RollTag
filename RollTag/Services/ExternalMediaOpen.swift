import AppKit
import Foundation
import UniformTypeIdentifiers

enum ExternalMediaOpen {
    static let quickTimeBundleID = "com.apple.QuickTimePlayerX"
    static let previewBundleID = "com.apple.Preview"

    struct AppChoice: Identifiable, Hashable {
        var url: URL
        var name: String
        var isDefault: Bool
        var id: String { url.standardizedFileURL.path }
    }

    static func preferredBundleID(for kind: MediaKind) -> String {
        kind == .image ? previewBundleID : quickTimeBundleID
    }

    static func displayName(for url: URL) -> String {
        let raw = FileManager.default.displayName(atPath: url.path)
        if raw.hasSuffix(".app") {
            return String(raw.dropLast(4))
        }
        return raw
    }

    static func menuApps(
        defaultApp: URL?,
        preferredApp: URL?,
        others: [URL],
        skipLastPathComponents: Set<String> = ["RollTag.app"]
    ) -> [AppChoice] {
        var seen = Set<String>()
        var result: [AppChoice] = []

        func add(_ url: URL?, isDefault: Bool) {
            guard let url else { return }
            if skipLastPathComponents.contains(url.lastPathComponent) { return }
            let key = url.standardizedFileURL.path.lowercased()
            guard seen.insert(key).inserted else { return }
            result.append(
                AppChoice(
                    url: url.standardizedFileURL,
                    name: displayName(for: url),
                    isDefault: isDefault
                )
            )
        }

        add(defaultApp, isDefault: true)
        add(preferredApp, isDefault: false)
        for url in others where result.count < 7 {
            add(url, isDefault: false)
        }
        return result
    }

    static func menuApps(for fileURL: URL, kind: MediaKind) -> [AppChoice] {
        let preferred = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: preferredBundleID(for: kind)
        )
        return menuApps(
            defaultApp: NSWorkspace.shared.urlForApplication(toOpen: fileURL),
            preferredApp: preferred,
            others: NSWorkspace.shared.urlsForApplications(toOpen: fileURL)
        )
    }

    static func open(_ fileURL: URL, with appURL: URL?, onError: @escaping @MainActor () -> Void) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let finish: (Error?) -> Void = { error in
            guard error != nil else { return }
            Task { @MainActor in
                onError()
            }
        }
        if let appURL {
            NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: configuration) { _, error in
                finish(error)
            }
        } else {
            NSWorkspace.shared.open(fileURL, configuration: configuration) { _, error in
                finish(error)
            }
        }
    }

    static func chooseApp(for fileURL: URL, from window: NSWindow?, onError: @escaping @MainActor () -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = String(localized: "openWith.choose.confirm")
        panel.message = String(localized: "openWith.choose.message")
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let appURL = panel.url else { return }
            open(fileURL, with: appURL, onError: onError)
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(panel.runModal())
        }
    }
}
