import Foundation

struct PreferenceStore {
    let configURL: URL
    private let fileManager: FileManager

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.configURL = homeDirectory.appendingPathComponent("rolltag/config.json")
    }

    func load() throws -> PreferenceFile {
        guard fileManager.fileExists(atPath: configURL.path) else {
            return .empty
        }
        let data = try Data(contentsOf: configURL)
        var file = try JSONDecoder().decode(PreferenceFile.self, from: data)
        if file.version == 0 {
            file.version = PreferenceFile.currentVersion
        }
        return file
    }

    func save(_ file: PreferenceFile) throws {
        let directory = configURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(file)
        try data.write(to: configURL, options: .atomic)
    }

    func addWarehouse(named name: String, path: String, bookmark: Data? = nil, to file: PreferenceFile) -> PreferenceFile {
        var next = file
        if next.warehouses.contains(where: { Self.normalized($0.path) == Self.normalized(path) }) {
            return next
        }
        let warehouse = WarehousePreference(
            id: UUID(),
            name: name.isEmpty ? URL(fileURLWithPath: path).lastPathComponent : name,
            path: path,
            bookmark: bookmark
        )
        next.warehouses.append(warehouse)
        return next
    }

    func updateWarehouse(id: UUID, name: String? = nil, path: String? = nil, bookmark: Data? = nil, in file: PreferenceFile) -> PreferenceFile {
        var next = file
        guard let index = next.warehouses.firstIndex(where: { $0.id == id }) else { return next }
        if let name { next.warehouses[index].name = name }
        if let path { next.warehouses[index].path = path }
        if let bookmark { next.warehouses[index].bookmark = bookmark }
        return next
    }

    func updateAI(selectedProvider: AIProvider?, in file: PreferenceFile) -> PreferenceFile {
        var next = file
        next.ai.selectedProvider = selectedProvider
        return next
    }

    func updateAIKey(provider: AIProvider, apiKey: String, model: String? = nil, in file: PreferenceFile) -> PreferenceFile {
        var next = file
        var settings = next.ai.settings(for: provider)
        settings.apiKey = apiKey
        if let model { settings.model = model }
        if settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, settings.model.isEmpty {
            next.ai.providers[provider] = nil
        } else {
            next.ai.providers[provider] = settings
        }
        return next
    }

    func updateSkipImplausibleCaptureDates(_ skip: Bool, in file: PreferenceFile) -> PreferenceFile {
        var next = file
        next.ai.skipImplausibleCaptureDates = skip
        return next
    }

    func removeWarehouse(id: UUID, from file: PreferenceFile) -> PreferenceFile {
        var next = file
        next.warehouses.removeAll { $0.id == id }
        return next
    }

    func isOnline(_ warehouse: WarehousePreference) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: warehouse.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    func bookmark(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    @discardableResult
    func startAccessing(_ warehouse: WarehousePreference) -> Bool {
        guard let bookmark = warehouse.bookmark else { return true }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            return fileManager.fileExists(atPath: warehouse.path)
        }
        return url.startAccessingSecurityScopedResource()
    }

    private static func normalized(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
