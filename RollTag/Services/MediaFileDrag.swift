import AppKit
import Foundation
import UniformTypeIdentifiers

enum MediaFileDrag {
    static let filenamesType = "NSFilenamesPboardType"
    static let uriListType = "text/uri-list"

    private static var activeSource: MediaFileDraggingSource?
    private static var isDragging = false

    static func targetIDs(startingAt id: UUID, selectedIDs: Set<UUID>, visibleIDs: [UUID]) -> [UUID] {
        guard selectedIDs.contains(id) else { return [id] }
        let ordered = visibleIDs.filter { selectedIDs.contains($0) }
        return ordered.isEmpty ? [id] : ordered
    }

    static func urls(ids: [UUID], resolve: (UUID) -> URL?) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for id in ids {
            guard let url = resolve(id)?.standardizedFileURL else { continue }
            guard seen.insert(url.path).inserted else { continue }
            result.append(url)
        }
        return result
    }

    static func existingFileURL(_ url: URL) -> URL? {
        let file = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else { return nil }
        return file
    }

    static func escapedPOSIXPaths(_ urls: [URL]) -> String {
        urls.map { escapePOSIXPath($0.path) }.joined(separator: " ")
    }

    static func uriList(_ urls: [URL]) -> String {
        urls.map(\.absoluteString).joined(separator: "\r\n") + "\r\n"
    }

    static func escapePOSIXPath(_ path: String) -> String {
        let special = CharacterSet(charactersIn: " \\'\"()[]{}*?$`!#&|;<>\t\n")
        var result = ""
        for scalar in path.unicodeScalars {
            if special.contains(scalar) {
                result.append("\\")
            }
            result.append(Character(scalar))
        }
        return result
    }

    static func beginSession(urls: [URL]) {
        guard !isDragging, !urls.isEmpty else { return }
        guard let event = NSApp.currentEvent,
              let view = event.window?.contentView ?? NSApp.keyWindow?.contentView
        else { return }

        isDragging = true
        let source = MediaFileDraggingSource()
        activeSource = source

        let icon = NSWorkspace.shared.icon(forFile: urls[0].path)
        icon.size = NSSize(width: 64, height: 64)
        let point = view.convert(event.locationInWindow, from: nil)
        let frame = NSRect(x: point.x - 32, y: point.y - 32, width: 64, height: 64)
        let items = urls.map { url -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: MediaFilePasteboardWriter(url: url, allURLs: urls))
            item.setDraggingFrame(frame, contents: icon)
            return item
        }

        let session = view.beginDraggingSession(with: items, event: event, source: source)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = urls.count > 1 ? .pile : .default
        writeSharedTypes(urls, to: session.draggingPasteboard)
    }

    static func writeSharedTypes(_ urls: [URL], to pasteboard: NSPasteboard) {
        guard !urls.isEmpty else { return }
        pasteboard.setPropertyList(urls.map(\.path), forType: NSPasteboard.PasteboardType(filenamesType))
        pasteboard.setString(escapedPOSIXPaths(urls), forType: .string)
        pasteboard.setString(uriList(urls), forType: NSPasteboard.PasteboardType(uriListType))
        if let first = urls.first {
            pasteboard.setString(first.absoluteString, forType: .fileURL)
            pasteboard.setString(first.absoluteString, forType: .URL)
        }
    }

    static func itemProvider(urls: [URL]) -> NSItemProvider {
        guard let first = urls.first else { return NSItemProvider() }
        let provider = NSItemProvider(object: first as NSURL)
        provider.suggestedName = first.lastPathComponent
        registerRepresentations(urls, on: provider)
        return provider
    }

    static func sessionDidEnd() {
        isDragging = false
        activeSource = nil
    }

    private static func registerRepresentations(_ urls: [URL], on provider: NSItemProvider) {
        let paths = urls.map(\.path)
        let text = escapedPOSIXPaths(urls)
        let list = uriList(urls)
        provider.registerDataRepresentation(forTypeIdentifier: filenamesType, visibility: .all) { completion in
            do {
                let data = try PropertyListSerialization.data(fromPropertyList: paths, format: .xml, options: 0)
                completion(data, nil)
            } catch {
                completion(nil, error)
            }
            return nil
        }
        provider.registerDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier, visibility: .all) { completion in
            completion(Data(text.utf8), nil)
            return nil
        }
        provider.registerDataRepresentation(forTypeIdentifier: UTType.url.identifier, visibility: .all) { completion in
            completion(Data(urls[0].absoluteString.utf8), nil)
            return nil
        }
        provider.registerDataRepresentation(forTypeIdentifier: uriListType, visibility: .all) { completion in
            completion(Data(list.utf8), nil)
            return nil
        }
        guard let first = urls.first else { return }
        let contentType = UTType(filenameExtension: first.pathExtension) ?? .data
        provider.registerFileRepresentation(
            forTypeIdentifier: UTType.fileURL.identifier,
            fileOptions: .openInPlace,
            visibility: .all
        ) { completion in
            completion(first, false, nil)
            return nil
        }
        provider.registerFileRepresentation(
            forTypeIdentifier: contentType.identifier,
            fileOptions: .openInPlace,
            visibility: .all
        ) { completion in
            completion(first, false, nil)
            return nil
        }
    }
}

final class MediaFileDraggingSource: NSObject, NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        [.copy, .generic, .link]
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        MediaFileDrag.sessionDidEnd()
    }
}

final class MediaFilePasteboardWriter: NSObject, NSPasteboardWriting {
    let url: URL
    let allURLs: [URL]

    init(url: URL, allURLs: [URL]) {
        self.url = url
        self.allURLs = allURLs
    }

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        [
            .fileURL,
            NSPasteboard.PasteboardType(MediaFileDrag.filenamesType),
            .URL,
            .string,
            NSPasteboard.PasteboardType(MediaFileDrag.uriListType),
        ]
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        switch type {
        case .fileURL:
            return (url as NSURL).pasteboardPropertyList(forType: .fileURL) ?? url.absoluteString
        case .URL:
            return url.absoluteString
        case .string:
            return MediaFileDrag.escapedPOSIXPaths(allURLs)
        default:
            if type.rawValue == MediaFileDrag.filenamesType {
                return allURLs.map(\.path)
            }
            if type.rawValue == MediaFileDrag.uriListType {
                return MediaFileDrag.uriList(allURLs)
            }
            return nil
        }
    }
}
