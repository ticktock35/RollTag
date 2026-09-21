import Foundation

struct ResolvedDuplicateGroup: Identifiable, Hashable {
    var warehouseID: UUID
    var group: DuplicateGroup
    var members: [Footage]

    var id: UUID { group.id }
}

enum DuplicateIndex {
    /// Groups already stored from `content_hash`. Folder scope only keeps groups that touch those paths.
    static func resolve(warehouses: [WarehouseRuntime], scopes: Set<FolderRef>) -> [ResolvedDuplicateGroup] {
        warehouses.flatMap { warehouse in
            warehouse.groups.compactMap { group -> ResolvedDuplicateGroup? in
                guard group.resolution == .unresolved, group.memberIDs.count > 1 else { return nil }
                let members = group.memberIDs.compactMap { warehouse.footageByID[$0] }
                    .sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
                guard members.count > 1 else { return nil }
                if !scopes.isEmpty {
                    let hits = members.contains { FootageFilter.matchesScopes(footage: $0, scopes: scopes) }
                    guard hits else { return nil }
                }
                return ResolvedDuplicateGroup(warehouseID: warehouse.id, group: group, members: members)
            }
        }
    }
}
