import Foundation
import SQLite3

final class WarehouseDatabase {
    private var db: OpaquePointer?
    let rootURL: URL
    let warehouseID: UUID

    var databaseURL: URL {
        rootURL
            .appendingPathComponent(MediaConstants.rolltagDirectory)
            .appendingPathComponent(MediaConstants.databaseName)
    }

    var thumbsURL: URL {
        rootURL
            .appendingPathComponent(MediaConstants.rolltagDirectory)
            .appendingPathComponent(MediaConstants.thumbsDirectory)
    }

    init(rootURL: URL, warehouseID: UUID) throws {
        self.rootURL = rootURL
        self.warehouseID = warehouseID
        let fm = FileManager.default
        try fm.createDirectory(at: thumbsURL, withIntermediateDirectories: true)
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(databaseURL.path, &db, flags, nil) != SQLITE_OK {
            throw WarehouseDBError.openFailed(String(cString: sqlite3_errmsg(db)))
        }
        try execute("PRAGMA foreign_keys = ON;")
        try execute("PRAGMA journal_mode = WAL;")
        try migrate()
    }

    deinit {
        sqlite3_close(db)
    }

    func allFootage() throws -> [Footage] {
        let sql = """
        SELECT id, relative_path, filename, size, mtime, content_hash, phash, status,
               duration, width, height, created_at, updated_at, parent_id, user_notes, metadata_json
        FROM footage
        ORDER BY filename COLLATE NOCASE;
        """
        let rows = try query(sql)
        let tags = try allTags()
        return rows.map { row in
            let id = UUID(uuidString: row["id"] ?? "") ?? UUID()
            return Footage(
                id: id,
                warehouseID: warehouseID,
                relativePath: row["relative_path"] ?? "",
                filename: row["filename"] ?? "",
                size: Int64(row["size"] ?? "0") ?? 0,
                mtime: Int64(row["mtime"] ?? "0") ?? 0,
                contentHash: row["content_hash"].flatMap { $0.isEmpty ? nil : $0 },
                phash: row["phash"].flatMap { $0.isEmpty ? nil : $0 },
                status: FootageStatus(rawValue: row["status"] ?? "available") ?? .available,
                duration: row["duration"].flatMap(Double.init),
                width: row["width"].flatMap(Int.init),
                height: row["height"].flatMap(Int.init),
                createdAt: Date(timeIntervalSince1970: Double(row["created_at"] ?? "0") ?? 0),
                updatedAt: Date(timeIntervalSince1970: Double(row["updated_at"] ?? "0") ?? 0),
                parentID: row["parent_id"].flatMap(UUID.init(uuidString:)),
                userNotes: row["user_notes"] ?? "",
                tags: tags[id] ?? [],
                capturedAt: decodeCapturedAt(row["metadata_json"])
            )
        }
    }

    func apply(outcome: ReconcileOutcome) throws {
        let existing = try Set(allFootage().map(\.id))
        for record in outcome.records {
            if existing.contains(record.id) {
                try update(record)
            } else {
                try insert(record)
            }
        }
        try refreshDuplicateGroups(hashes: outcome.duplicateHashes)
    }

    func insert(_ snapshot: FootageSnapshot) throws {
        let now = Date().timeIntervalSince1970
        try execute(
            """
            INSERT INTO footage (
                id, relative_path, filename, size, mtime, content_hash, phash, status,
                duration, width, height, created_at, updated_at, parent_id, user_notes, metadata_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            params: [
                snapshot.id.uuidString,
                snapshot.relativePath,
                snapshot.filename,
                snapshot.size,
                snapshot.mtime,
                snapshot.contentHash as Any,
                snapshot.phash as Any,
                snapshot.status.rawValue,
                snapshot.duration as Any,
                snapshot.width as Any,
                snapshot.height as Any,
                now,
                now,
                snapshot.parentID?.uuidString as Any,
                snapshot.userNotes,
                encodeMetadata(capturedAt: snapshot.capturedAt)
            ]
        )
        try replaceTags(footageID: snapshot.id, tags: snapshot.tags)
    }

    func update(_ snapshot: FootageSnapshot) throws {
        try execute(
            """
            UPDATE footage SET
                relative_path = ?, filename = ?, size = ?, mtime = ?, content_hash = ?, phash = ?,
                status = ?, duration = ?, width = ?, height = ?, updated_at = ?, parent_id = ?,
                user_notes = ?, metadata_json = ?
            WHERE id = ?;
            """,
            params: [
                snapshot.relativePath,
                snapshot.filename,
                snapshot.size,
                snapshot.mtime,
                snapshot.contentHash as Any,
                snapshot.phash as Any,
                snapshot.status.rawValue,
                snapshot.duration as Any,
                snapshot.width as Any,
                snapshot.height as Any,
                Date().timeIntervalSince1970,
                snapshot.parentID?.uuidString as Any,
                snapshot.userNotes,
                encodeMetadata(capturedAt: snapshot.capturedAt),
                snapshot.id.uuidString
            ]
        )
        try replaceTags(footageID: snapshot.id, tags: snapshot.tags)
    }

    func updateNotes(id: UUID, notes: String) throws {
        try execute("UPDATE footage SET user_notes = ?, updated_at = ? WHERE id = ?;", params: [notes, Date().timeIntervalSince1970, id.uuidString])
    }

    func updateAnalysis(id: UUID, phash: String?, duration: Double?, width: Int?, height: Int?, capturedAt: Date?) throws {
        try execute(
            "UPDATE footage SET phash = ?, duration = ?, width = ?, height = ?, metadata_json = ?, updated_at = ? WHERE id = ?;",
            params: [
                phash as Any,
                duration as Any,
                width as Any,
                height as Any,
                encodeMetadata(capturedAt: capturedAt),
                Date().timeIntervalSince1970,
                id.uuidString
            ]
        )
    }

    func addTags(_ tags: [TagAssignment], to ids: [UUID]) throws {
        for id in ids {
            for tag in TagAssignment.uniqued(tags) {
                try execute(
                    "DELETE FROM tags WHERE footage_id = ? AND category = ? AND value = ?;",
                    params: [id.uuidString, tag.category, tag.value]
                )
                try execute(
                    "INSERT INTO tags (footage_id, category, value, source) VALUES (?, ?, ?, ?);",
                    params: [id.uuidString, tag.category, tag.value, tag.source]
                )
            }
        }
    }

    func removeTags(_ tags: [TagAssignment], from ids: [UUID]) throws {
        for id in ids {
            for tag in tags {
                try execute(
                    "DELETE FROM tags WHERE footage_id = ? AND category = ? AND value = ?;",
                    params: [id.uuidString, tag.category, tag.value]
                )
            }
        }
    }

    func duplicateGroups() throws -> [DuplicateGroup] {
        let groups = try query("SELECT id, content_hash, resolution FROM duplicate_groups;")
        let members = try query("SELECT group_id, footage_id FROM duplicate_members;")
        let grouped = Dictionary(grouping: members, by: { $0["group_id"] ?? "" })
        return groups.map { row in
            let idString = row["id"] ?? ""
            return DuplicateGroup(
                id: UUID(uuidString: idString) ?? UUID(),
                contentHash: row["content_hash"] ?? "",
                resolution: DuplicateResolution(rawValue: row["resolution"] ?? "unresolved") ?? .unresolved,
                memberIDs: (grouped[idString] ?? []).compactMap { $0["footage_id"].flatMap(UUID.init(uuidString:)) }
            )
        }
    }

    func removeFootage(id: UUID) throws {
        try execute("DELETE FROM duplicate_members WHERE footage_id = ?;", params: [id.uuidString])
        try execute("DELETE FROM footage WHERE id = ?;", params: [id.uuidString])
    }

    func deleteDuplicateGroup(id: UUID) throws {
        try execute("DELETE FROM duplicate_groups WHERE id = ?;", params: [id.uuidString])
    }

    func setResolution(groupID: UUID, resolution: DuplicateResolution) throws {
        try execute(
            "UPDATE duplicate_groups SET resolution = ? WHERE id = ?;",
            params: [resolution.rawValue, groupID.uuidString]
        )
    }

    func mergeMetadata(keeperID: UUID, from others: [Footage], unionTags: Bool) throws {
        let keeperTags = try tags(for: keeperID)
        var next = Set(keeperTags)
        if unionTags {
            for item in others { next.formUnion(item.tags) }
        }
        try replaceTags(footageID: keeperID, tags: Array(next))
        if unionTags {
            for item in others {
                try replaceTags(footageID: item.id, tags: Array(next))
            }
        } else {
            for item in others {
                try replaceTags(footageID: item.id, tags: Array(next))
            }
        }
        if let notes = others.map(\.userNotes).first(where: { !$0.isEmpty }) {
            let current = try query("SELECT user_notes FROM footage WHERE id = ?;", params: [keeperID.uuidString]).first?["user_notes"] ?? ""
            if current.isEmpty {
                try updateNotes(id: keeperID, notes: notes)
            }
        }
    }

    func refreshDuplicateGroups(hashes: [String]) throws {
        let previous = try query("SELECT content_hash, resolution FROM duplicate_groups;")
        var previousByHash: [String: String] = [:]
        for row in previous {
            if let hash = row["content_hash"], !hash.isEmpty {
                previousByHash[hash] = row["resolution"] ?? DuplicateResolution.unresolved.rawValue
            }
        }
        try execute("DELETE FROM duplicate_members;")
        try execute("DELETE FROM duplicate_groups;")
        let footage = try allFootage()
        let grouped = Dictionary(grouping: footage.filter { $0.status == .available && $0.contentHash != nil }) { $0.contentHash! }
        for (hash, items) in grouped where items.count > 1 {
            let groupID = UUID()
            try execute(
                "INSERT INTO duplicate_groups (id, content_hash, resolution) VALUES (?, ?, ?);",
                params: [groupID.uuidString, hash, previousByHash[hash] ?? DuplicateResolution.unresolved.rawValue]
            )
            for item in items {
                try execute(
                    "INSERT INTO duplicate_members (group_id, footage_id) VALUES (?, ?);",
                    params: [groupID.uuidString, item.id.uuidString]
                )
            }
        }
        _ = hashes
    }

    private func migrate() throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS schema_info (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        """)
        try execute("""
        CREATE TABLE IF NOT EXISTS footage (
            id TEXT PRIMARY KEY,
            relative_path TEXT NOT NULL UNIQUE,
            filename TEXT NOT NULL,
            size INTEGER NOT NULL,
            mtime INTEGER NOT NULL,
            content_hash TEXT,
            phash TEXT,
            status TEXT NOT NULL,
            duration REAL,
            width INTEGER,
            height INTEGER,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            parent_id TEXT,
            user_notes TEXT,
            embedding_id TEXT,
            ai_tags_json TEXT,
            moved_from TEXT,
            davinci_id TEXT,
            metadata_json TEXT
        );
        """)
        try execute("""
        CREATE TABLE IF NOT EXISTS tags (
            footage_id TEXT NOT NULL,
            category TEXT NOT NULL,
            value TEXT NOT NULL,
            source TEXT NOT NULL DEFAULT 'user',
            PRIMARY KEY (footage_id, category, value, source),
            FOREIGN KEY (footage_id) REFERENCES footage(id) ON DELETE CASCADE
        );
        """)
        try execute("""
        CREATE TABLE IF NOT EXISTS duplicate_groups (
            id TEXT PRIMARY KEY,
            content_hash TEXT NOT NULL,
            resolution TEXT NOT NULL
        );
        """)
        try execute("""
        CREATE TABLE IF NOT EXISTS duplicate_members (
            group_id TEXT NOT NULL,
            footage_id TEXT NOT NULL,
            PRIMARY KEY (group_id, footage_id),
            FOREIGN KEY (group_id) REFERENCES duplicate_groups(id) ON DELETE CASCADE
        );
        """)
        try execute("INSERT OR IGNORE INTO schema_info (key, value) VALUES ('version', '1');")
    }

    private func allTags() throws -> [UUID: [TagAssignment]] {
        let rows = try query("SELECT footage_id, category, value, source FROM tags;")
        var result: [UUID: [TagAssignment]] = [:]
        for row in rows {
            guard let id = row["footage_id"].flatMap(UUID.init(uuidString:)) else { continue }
            result[id, default: []].append(
                TagAssignment(category: row["category"] ?? "", value: row["value"] ?? "", source: row["source"] ?? "user")
            )
        }
        return result.mapValues { TagAssignment.uniqued($0) }
    }

    private func tags(for id: UUID) throws -> [TagAssignment] {
        TagAssignment.uniqued(
            try query(
                "SELECT category, value, source FROM tags WHERE footage_id = ?;",
                params: [id.uuidString]
            ).map {
                TagAssignment(category: $0["category"] ?? "", value: $0["value"] ?? "", source: $0["source"] ?? "user")
            }
        )
    }

    private func replaceTags(footageID: UUID, tags: [TagAssignment]) throws {
        try execute("DELETE FROM tags WHERE footage_id = ?;", params: [footageID.uuidString])
        for tag in TagAssignment.uniqued(tags) {
            try execute(
                "INSERT INTO tags (footage_id, category, value, source) VALUES (?, ?, ?, ?);",
                params: [footageID.uuidString, tag.category, tag.value, tag.source]
            )
        }
    }

    private func encodeMetadata(capturedAt: Date?) -> String? {
        guard let capturedAt else { return nil }
        let data = try? JSONSerialization.data(withJSONObject: ["capturedAt": capturedAt.timeIntervalSince1970])
        return data.flatMap { String(data: $0, encoding: .utf8) }
    }

    private func decodeCapturedAt(_ raw: String?) -> Date? {
        guard let raw, let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = object["capturedAt"] as? Double
        else { return nil }
        return Date(timeIntervalSince1970: value)
    }

    private func execute(_ sql: String, params: [Any] = []) throws {
        let statement = try prepare(sql, params: params)
        defer { sqlite3_finalize(statement) }
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { break }
            if status == SQLITE_ROW { continue }
            throw WarehouseDBError.executeFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func query(_ sql: String, params: [Any] = []) throws -> [[String: String]] {
        let statement = try prepare(sql, params: params)
        defer { sqlite3_finalize(statement) }
        var rows: [[String: String]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: String] = [:]
            let count = sqlite3_column_count(statement)
            for index in 0..<count {
                let name = String(cString: sqlite3_column_name(statement, index))
                if sqlite3_column_type(statement, index) == SQLITE_NULL {
                    row[name] = ""
                } else if let text = sqlite3_column_text(statement, index) {
                    row[name] = String(cString: text)
                }
            }
            rows.append(row)
        }
        return rows
    }

    private func prepare(_ sql: String, params: [Any]) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
            throw WarehouseDBError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        for (offset, param) in params.enumerated() {
            bind(statement, index: Int32(offset + 1), param)
        }
        return statement
    }

    private func bind(_ statement: OpaquePointer?, index: Int32, _ param: Any) {
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        if param is NSNull {
            sqlite3_bind_null(statement, index)
            return
        }
        switch param {
        case let value as String:
            sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
        case let value as Int64:
            sqlite3_bind_int64(statement, index, value)
        case let value as Int:
            sqlite3_bind_int64(statement, index, Int64(value))
        case let value as Double:
            sqlite3_bind_double(statement, index, value)
        case let value as Date:
            sqlite3_bind_double(statement, index, value.timeIntervalSince1970)
        default:
            let mirror = Mirror(reflecting: param)
            if mirror.displayStyle == .optional {
                if let child = mirror.children.first {
                    bind(statement, index: index, child.value)
                } else {
                    sqlite3_bind_null(statement, index)
                }
                return
            }
            sqlite3_bind_text(statement, index, "\(param)", -1, SQLITE_TRANSIENT)
        }
    }
}

enum WarehouseDBError: Error, LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case executeFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let message): return message
        case .prepareFailed(let message): return message
        case .executeFailed(let message): return message
        }
    }
}

extension Footage {
    func snapshot() -> FootageSnapshot {
        FootageSnapshot(
            id: id,
            relativePath: relativePath,
            filename: filename,
            size: size,
            mtime: mtime,
            contentHash: contentHash,
            phash: phash,
            status: status,
            tags: tags,
            userNotes: userNotes,
            parentID: parentID,
            duration: duration,
            width: width,
            height: height,
            capturedAt: capturedAt,
            needsReanalysis: false
        )
    }
}
