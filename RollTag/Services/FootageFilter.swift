import Foundation

enum FootageFilter {
    static func include(
        footage: Footage,
        isOnline: Bool,
        selection: SidebarSelection,
        isDuplicate: Bool,
        folderScopes: Set<FolderRef> = []
    ) -> Bool {
        guard matchesSelection(
            footage: footage,
            isOnline: isOnline,
            selection: selection,
            isDuplicate: isDuplicate,
            folderScopes: folderScopes
        ) else { return false }
        return matchesScopes(footage: footage, scopes: resolvedScopes(selection: selection, folderScopes: folderScopes))
    }

    static func resolvedScopes(selection: SidebarSelection, folderScopes: Set<FolderRef>) -> Set<FolderRef> {
        if !folderScopes.isEmpty { return folderScopes }
        if case .warehouseFolder(let id, let path) = selection {
            return [FolderRef(warehouseID: id, relativePath: path)]
        }
        return []
    }

    static func matchesScopes(footage: Footage, scopes: Set<FolderRef>) -> Bool {
        guard !scopes.isEmpty else { return true }
        return scopes.contains { scope in
            footage.warehouseID == scope.warehouseID
                && WarehouseFolderTree.contains(directoryPath: footage.directoryPath, folder: scope.relativePath)
        }
    }

    static func duplicateGroup(
        _ memberIDs: Set<UUID>,
        members: [Footage],
        intersects scopes: Set<FolderRef>
    ) -> Bool {
        guard !scopes.isEmpty else { return true }
        return members.contains { footage in
            memberIDs.contains(footage.id) && matchesScopes(footage: footage, scopes: scopes)
        }
    }

    private static func matchesSelection(
        footage: Footage,
        isOnline: Bool,
        selection: SidebarSelection,
        isDuplicate: Bool,
        folderScopes: Set<FolderRef>
    ) -> Bool {
        switch selection {
        case .collection(.all):
            return isOnline && footage.status == .available
        case .collection(.tagged):
            return isOnline && footage.status == .available && !footage.tags.isEmpty
        case .collection(.untagged):
            return isOnline && footage.status == .available && footage.tags.isEmpty
        case .collection(.missing):
            return footage.status == .missing
        case .collection(.duplicates):
            return isOnline && isDuplicate
        case .warehouse(let id):
            return footage.warehouseID == id && isOnline && footage.status == .available
        case .warehouseFolder(let id, _):
            guard isOnline, footage.status == .available else { return false }
            if folderScopes.isEmpty {
                return footage.warehouseID == id
            }
            return true
        case .tagCategory(let category):
            return isOnline
                && footage.status == .available
                && footage.tags.contains { $0.category == category }
        }
    }

    static func populatedCategories(
        from footage: [Footage],
        catalog: TagCatalog,
        locale: String,
        customTitle: String
    ) -> [BrowsableTagCategory] {
        let used = Set(
            footage
                .filter { $0.status == .available && !$0.tags.isEmpty }
                .flatMap(\.tags)
                .map(\.category)
        )
        var result: [BrowsableTagCategory] = catalog.categories
            .filter { used.contains($0.id) }
            .map { BrowsableTagCategory(id: $0.id, title: $0.localizedName(locale: locale)) }
        if used.contains(TagAssignment.customCategory) {
            result.append(BrowsableTagCategory(id: TagAssignment.customCategory, title: customTitle))
        }
        return result
    }

    static func aiTaggableIDs(
        warehouses: [WarehouseRuntime],
        selection: SidebarSelection,
        folderScopes: Set<FolderRef>
    ) -> [UUID] {
        warehouses.flatMap { warehouse in
            warehouse.footage.compactMap { footage in
                guard footage.canAITag else { return nil }
                guard include(
                    footage: footage,
                    isOnline: warehouse.isOnline,
                    selection: selection,
                    isDuplicate: false,
                    folderScopes: folderScopes
                ) else { return nil }
                return footage.id
            }
        }
    }

    static func silentAITargetIDs(clicked: UUID, selectedIDs: Set<UUID>) -> [UUID] {
        selectedIDs.contains(clicked) ? Array(selectedIDs) : [clicked]
    }

    /// Sidebar badges: file counts for All / Tagged / Untagged / Missing; `duplicateGroups` is unresolved groups.
    static func collectionCounts(
        warehouses: [WarehouseRuntime],
        scopes: Set<FolderRef>,
        duplicateGroups: Int
    ) -> SmartCollectionCounts {
        var counts = SmartCollectionCounts(duplicates: duplicateGroups)
        for warehouse in warehouses {
            for footage in warehouse.footage {
                guard matchesScopes(footage: footage, scopes: scopes) else { continue }
                if footage.status == .missing {
                    counts.missing += 1
                    continue
                }
                guard warehouse.isOnline, footage.status == .available else { continue }
                counts.all += 1
                if footage.tags.isEmpty {
                    counts.untagged += 1
                } else {
                    counts.tagged += 1
                }
            }
        }
        return counts
    }
}

struct SmartCollectionCounts: Equatable {
    var all = 0
    var tagged = 0
    var untagged = 0
    var missing = 0
    var duplicates = 0

    func value(for collection: SmartCollection) -> Int {
        switch collection {
        case .all: return all
        case .tagged: return tagged
        case .untagged: return untagged
        case .missing: return missing
        case .duplicates: return duplicates
        }
    }
}

struct BrowsableTagCategory: Identifiable, Hashable {
    var id: String
    var title: String
}
