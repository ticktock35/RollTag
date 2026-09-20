import Foundation

enum FootageFilter {
    static func include(
        footage: Footage,
        isOnline: Bool,
        selection: SidebarSelection,
        isDuplicate: Bool
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
}

struct BrowsableTagCategory: Identifiable, Hashable {
    var id: String
    var title: String
}
