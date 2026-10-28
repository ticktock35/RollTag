import Foundation

struct RetouchCandidate: Identifiable, Hashable {
    var warehouseID: UUID
    var original: Footage
    var edited: Footage
    var distance: Int

    var id: UUID { edited.id }
}

enum RetouchStore {
    static func load(root: URL) -> Set<UUID> {
        let url = fileURL(root: root)
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoded = try? JSONDecoder().decode(RetouchReviewFile.self, from: data)
        return Set(decoded?.declinedIDs ?? [])
    }

    static func save(_ declinedIDs: Set<UUID>, root: URL) throws {
        let url = fileURL(root: root)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(RetouchReviewFile(declinedIDs: declinedIDs.sorted { $0.uuidString < $1.uuidString })).write(to: url, options: .atomic)
    }

    static func fileURL(root: URL) -> URL {
        root
            .appendingPathComponent(MediaConstants.rolltagDirectory)
            .appendingPathComponent(MediaConstants.retouchReviewName)
    }
}

private struct RetouchReviewFile: Codable {
    var declinedIDs: [UUID]
}

enum RetouchIndex {
    static func resolve(warehouses: [WarehouseRuntime], scopes: Set<FolderRef>) -> [RetouchCandidate] {
        warehouses.flatMap { warehouse -> [RetouchCandidate] in
            guard warehouse.isOnline else { return [] }
            let members = warehouse.footage.filter { $0.status == .available }
            let zone = ItineraryBuilder.shootingTimeZone(from: members)
            let offsets = warehouse.gpx.offsets
            let declined = warehouse.declinedRetouchIDs
            return members.compactMap { edited -> RetouchCandidate? in
                guard !declined.contains(edited.id), !edited.hasRetouchTag else { return nil }
                guard let match = ItineraryBuilder.editedOriginal(
                    for: edited,
                    in: members,
                    zone: zone,
                    offsets: offsets
                ) else { return nil }
                guard let original = warehouse.footageByID[match.id] else { return nil }
                if !scopes.isEmpty {
                    let hits = [edited, original].contains { FootageFilter.matchesScopes(footage: $0, scopes: scopes) }
                    guard hits else { return nil }
                }
                let distance: Int
                if let left = edited.phash, let right = original.phash {
                    distance = SearchService.hamming(left, right)
                } else {
                    distance = 0
                }
                return RetouchCandidate(
                    warehouseID: warehouse.id,
                    original: original,
                    edited: edited,
                    distance: distance
                )
            }
            .sorted { lhs, rhs in
                let left = lhs.edited.capturedAt ?? .distantPast
                let right = rhs.edited.capturedAt ?? .distantPast
                if left != right { return left < right }
                return lhs.edited.filename.localizedStandardCompare(rhs.edited.filename) == .orderedAscending
            }
        }
    }
}
