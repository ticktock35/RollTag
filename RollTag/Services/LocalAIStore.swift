import Foundation

enum LocalAIStore {
    nonisolated(unsafe) static var customHome: URL?

    static var home: URL {
        customHome ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("rolltag")
    }

    static var modelsRoot: URL {
        home.appendingPathComponent("models")
    }

    static var florence2Root: URL {
        modelsRoot.appendingPathComponent("florence2")
    }

    static var ramPlusRoot: URL {
        modelsRoot.appendingPathComponent("ram_plus")
    }

    static func modelURL(for scheme: LocalAIScheme) -> URL? {
        switch scheme {
        case .appleVision:
            return nil
        case .florence2Base:
            return florence2Root.appendingPathComponent("model.onnx")
        case .ramPlus:
            return ramPlusRoot.appendingPathComponent("model.onnx")
        }
    }

    static func downloadURL(for scheme: LocalAIScheme) -> URL? {
        switch scheme {
        case .appleVision:
            return nil
        case .florence2Base:
            return URL(string: "https://huggingface.co/onnx-community/Florence-2-base/resolve/main/onnx/decoder_model_merged.onnx")
        case .ramPlus:
            return URL(string: "https://huggingface.co/xinyu1205/recognize-anything-plus-model/resolve/main/ram_plus_swin_large_14m.pth")
        }
    }

    static func modelSizeString(for scheme: LocalAIScheme) -> String {
        switch scheme {
        case .appleVision:
            return "0 GB"
        case .florence2Base:
            return "~370 MB"
        case .ramPlus:
            return "~2.8 GB"
        }
    }

    static func formattedInstalledSize(scheme: LocalAIScheme) -> String? {
        guard let bytes = installedFileSize(scheme: scheme) else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }

    static func displaySizeString(for scheme: LocalAIScheme) -> String {
        if isInstalled(scheme: scheme), let formatted = formattedInstalledSize(scheme: scheme) {
            return formatted
        }
        return modelSizeString(for: scheme)
    }

    static func isInstalled(scheme: LocalAIScheme) -> Bool {
        switch scheme {
        case .appleVision:
            return true
        case .florence2Base:
            guard let modelURL = modelURL(for: .florence2Base) else { return false }
            return FileManager.default.fileExists(atPath: modelURL.path)
                && (try? modelURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 > 1_000_000 } == true
        case .ramPlus:
            guard let modelURL = modelURL(for: .ramPlus) else { return false }
            return FileManager.default.fileExists(atPath: modelURL.path)
                && (try? modelURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 > 1_000_000 } == true
        }
    }

    static func installedFileSize(scheme: LocalAIScheme) -> Int64? {
        guard let url = modelURL(for: scheme),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) }
    }

    static func deleteModel(scheme: LocalAIScheme) throws {
        let fm = FileManager.default
        switch scheme {
        case .appleVision:
            break
        case .florence2Base:
            if fm.fileExists(atPath: florence2Root.path) {
                try fm.removeItem(at: florence2Root)
            }
        case .ramPlus:
            if fm.fileExists(atPath: ramPlusRoot.path) {
                try fm.removeItem(at: ramPlusRoot)
            }
        }
    }

    static func cleanupLegacyJoyTag(in baseHome: URL) {
        let fm = FileManager.default
        let legacyFolders = [
            baseHome.appendingPathComponent("joytag"),
            baseHome.appendingPathComponent("models/joytag"),
        ]
        for folder in legacyFolders where fm.fileExists(atPath: folder.path) {
            try? fm.removeItem(at: folder)
        }
    }

    static func cleanupLegacyJoyTagIfNeeded() {
        cleanupLegacyJoyTag(in: home)
    }
}
