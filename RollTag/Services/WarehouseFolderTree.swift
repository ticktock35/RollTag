import Foundation

struct WarehouseFolderNode: Identifiable, Hashable {
    var warehouseID: UUID
    /// Empty path is the warehouse root (whole library).
    var relativePath: String
    var name: String
    var children: [WarehouseFolderNode]?

    var id: String {
        relativePath.isEmpty ? warehouseID.uuidString : "\(warehouseID.uuidString)/\(relativePath)"
    }

    var isWarehouseRoot: Bool { relativePath.isEmpty }

    var displayName: String {
        relativePath.isEmpty ? name : (relativePath as NSString).lastPathComponent
    }
}

enum WarehouseFolderTree {
    static func normalize(_ path: String) -> String {
        path
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty && $0 != "." }
            .joined(separator: "/")
    }

    static func contains(directoryPath: String, folder: String) -> Bool {
        let dir = normalize(directoryPath)
        let scope = normalize(folder)
        guard !scope.isEmpty else { return true }
        return dir == scope || dir.hasPrefix(scope + "/")
    }

    static func nodes(warehouseID: UUID, from footage: [Footage]) -> [WarehouseFolderNode] {
        var directories = Set<String>()
        for item in footage where item.status == .available {
            let dir = normalize(item.directoryPath)
            guard !dir.isEmpty else { continue }
            var current = dir
            while !current.isEmpty {
                let parts = current.split(separator: "/").map(String.init)
                if parts.contains(where: { $0.hasPrefix(".") }) {
                    current = parent(of: current)
                    continue
                }
                directories.insert(current)
                current = parent(of: current)
            }
        }

        let root = NodeBuilder(name: "", path: "")
        for path in directories {
            root.insert(normalize(path).split(separator: "/").map(String.init), prefix: "")
        }
        return root.childNodes(warehouseID: warehouseID)
    }

    static func flattenedPaths(from nodes: [WarehouseFolderNode]) -> [String] {
        var paths: [String] = []
        func walk(_ nodes: [WarehouseFolderNode]) {
            for node in nodes {
                if !node.relativePath.isEmpty {
                    paths.append(node.relativePath)
                }
                if let children = node.children {
                    walk(children)
                }
            }
        }
        walk(nodes)
        return paths.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func outlineRoot(warehouseID: UUID, name: String, footage: [Footage]) -> WarehouseFolderNode {
        let folders = nodes(warehouseID: warehouseID, from: footage)
        return WarehouseFolderNode(
            warehouseID: warehouseID,
            relativePath: "",
            name: name,
            children: folders.isEmpty ? nil : folders
        )
    }

    private static func parent(of path: String) -> String {
        let parent = (path as NSString).deletingLastPathComponent
        if parent.isEmpty || parent == "." || parent == path { return "" }
        return normalize(parent)
    }
}

private final class NodeBuilder {
    var name: String
    var path: String
    var kids: [String: NodeBuilder] = [:]

    init(name: String, path: String) {
        self.name = name
        self.path = path
    }

    func insert(_ parts: [String], prefix: String) {
        guard let first = parts.first else { return }
        let nextPath = prefix.isEmpty ? first : prefix + "/" + first
        let child = kids[first] ?? NodeBuilder(name: first, path: nextPath)
        if parts.count > 1 {
            child.insert(Array(parts.dropFirst()), prefix: nextPath)
        }
        kids[first] = child
    }

    func childNodes(warehouseID: UUID) -> [WarehouseFolderNode] {
        kids.values
            .map { $0.node(warehouseID: warehouseID) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func node(warehouseID: UUID) -> WarehouseFolderNode {
        let children = childNodes(warehouseID: warehouseID)
        return WarehouseFolderNode(
            warehouseID: warehouseID,
            relativePath: path,
            name: name,
            children: children.isEmpty ? nil : children
        )
    }
}
