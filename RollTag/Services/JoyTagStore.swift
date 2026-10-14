import Foundation

enum JoyTagStore {
    static let imageSize = 448
    static let threshold = 0.4
    static let maxKeywords = 24
    static let frameLimit = 2
    static let modelRepo = "fancyfeast/joytag"

    static var home: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("rolltag")
    }

    static var root: URL { home.appendingPathComponent("joytag") }
    static var legacyRoot: URL { home.appendingPathComponent("models/joytag") }

    static var modelURL: URL { root.appendingPathComponent("model.onnx") }
    static var tagsURL: URL { root.appendingPathComponent("top_tags.txt") }

    static var isInstalled: Bool {
        migrateLegacyIfNeeded()
        return isInstalled(at: root)
    }

    static func migrateLegacyIfNeeded() {
        let fm = FileManager.default
        if isInstalled(at: root) { return }
        guard isInstalled(at: legacyRoot) else { return }
        try? fm.createDirectory(at: home, withIntermediateDirectories: true)
        if fm.fileExists(atPath: root.path) {
            try? fm.removeItem(at: root)
        }
        try? fm.moveItem(at: legacyRoot, to: root)
        let models = home.appendingPathComponent("models")
        if let leftover = try? fm.contentsOfDirectory(atPath: models.path), leftover.isEmpty {
            try? fm.removeItem(at: models)
        }
    }

    private static func isInstalled(at folder: URL) -> Bool {
        let model = folder.appendingPathComponent("model.onnx")
        let tags = folder.appendingPathComponent("top_tags.txt")
        return FileManager.default.fileExists(atPath: model.path)
            && FileManager.default.fileExists(atPath: tags.path)
            && (try? model.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 > 1_000_000 } == true
    }

    static func loadTags() throws -> [String] {
        let text = try String(contentsOf: tagsURL, encoding: .utf8)
        return text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static func remove() throws {
        let fm = FileManager.default
        for folder in [root, legacyRoot] where fm.fileExists(atPath: folder.path) {
            try fm.removeItem(at: folder)
        }
    }

    static func huggingfaceURL(_ filename: String) -> URL {
        URL(string: "https://huggingface.co/\(modelRepo)/resolve/main/\(filename)?download=true")!
    }
}

enum JoyTagTags {
    static func displayKeyword(_ raw: String) -> String? {
        let spaced = raw.replacingOccurrences(of: "_", with: " ")
        return StockKeywordExpander.gettyKeyword(spaced)
    }

    static func keywords(tags: [String], scores: [Float], threshold: Double = JoyTagStore.threshold, limit: Int = JoyTagStore.maxKeywords) -> [String] {
        let pairs = zip(tags, scores)
            .filter { $0.1 >= Float(threshold) }
            .sorted { $0.1 > $1.1 }
        var seen = Set<String>()
        var result: [String] = []
        for (tag, _) in pairs {
            guard let keyword = displayKeyword(tag) else { continue }
            guard seen.insert(keyword).inserted else { continue }
            result.append(keyword)
            if result.count >= limit { break }
        }
        return result
    }
}
