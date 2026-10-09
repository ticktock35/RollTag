import Foundation

enum ReconcileService {
    static let hashConcurrency = 4

    static func isStableMatch(_ current: FootageSnapshot, file: DiskEntry) -> Bool {
        current.size == file.size
            && current.mtime == file.mtime
            && current.status == .available
            && current.contentHash != nil
    }

    static func pathsNeedingHash(existing: [FootageSnapshot], disk: [DiskEntry]) -> [String] {
        var byPath: [String: FootageSnapshot] = [:]
        byPath.reserveCapacity(existing.count)
        for record in existing where byPath[record.relativePath] == nil {
            byPath[record.relativePath] = record
        }
        return disk.compactMap { file in
            if let current = byPath[file.relativePath], isStableMatch(current, file: file) {
                return nil
            }
            return file.relativePath
        }
    }

    static func plan(
        existing: [FootageSnapshot],
        disk: [DiskEntry],
        hashOf: (String) -> String,
        onProgress: ((String, Int, Int) -> Void)? = nil
    ) -> ReconcileOutcome {
        var records = existing
        var hashedPaths: [String] = []
        var hashCache: [String: String] = [:]
        var indexByID: [UUID: Int] = [:]
        var indexByPath: [String: Int] = [:]
        indexByID.reserveCapacity(records.count)
        indexByPath.reserveCapacity(records.count)
        for (index, record) in records.enumerated() {
            indexByID[record.id] = index
            if indexByPath[record.relativePath] == nil {
                indexByPath[record.relativePath] = index
            }
        }

        func hash(_ relativePath: String) -> String {
            if let cached = hashCache[relativePath] { return cached }
            hashedPaths.append(relativePath)
            let value = hashOf(relativePath)
            hashCache[relativePath] = value
            return value
        }

        func replace(_ snapshot: FootageSnapshot) {
            if let index = indexByID[snapshot.id] {
                let oldPath = records[index].relativePath
                records[index] = snapshot
                if oldPath != snapshot.relativePath, indexByPath[oldPath] == index {
                    indexByPath.removeValue(forKey: oldPath)
                }
                indexByPath[snapshot.relativePath] = index
                return
            }
            records.append(snapshot)
            let index = records.count - 1
            indexByID[snapshot.id] = index
            indexByPath[snapshot.relativePath] = index
        }

        let diskByPath = Dictionary(uniqueKeysWithValues: disk.map { ($0.relativePath, $0) })
        var claimedDisk = Set<String>()
        let total = disk.count
        var processed = 0

        func begin(_ path: String) {
            onProgress?(path, processed, max(total, 1))
        }

        func tick(_ path: String) {
            processed += 1
            onProgress?(path, processed, total)
        }

        for file in disk {
            guard let index = indexByPath[file.relativePath] else { continue }
            var current = records[index]
            claimedDisk.insert(file.relativePath)

            let filename = file.filename
            if isStableMatch(current, file: file) {
                tick(file.relativePath)
                continue
            }

            begin(file.relativePath)
            let newHash = hash(file.relativePath)
            if let oldHash = current.contentHash, oldHash == newHash {
                current.size = file.size
                current.mtime = file.mtime
                current.filename = filename
                current.status = .available
                current.needsReanalysis = false
                replace(current)
            } else if current.contentHash == nil {
                current.contentHash = newHash
                current.size = file.size
                current.mtime = file.mtime
                current.filename = filename
                current.status = .available
                replace(current)
            } else {
                current.contentHash = newHash
                current.phash = nil
                current.size = file.size
                current.mtime = file.mtime
                current.filename = filename
                current.status = .available
                current.needsReanalysis = true
                replace(current)
            }
            tick(file.relativePath)
        }

        var unlocated = records.filter { diskByPath[$0.relativePath] == nil }

        for file in disk where !claimedDisk.contains(file.relativePath) {
            begin(file.relativePath)
            let newHash = hash(file.relativePath)

            if let matchIndex = unlocated.firstIndex(where: { $0.contentHash == newHash }) {
                var restored = unlocated.remove(at: matchIndex)
                restored.relativePath = file.relativePath
                restored.filename = file.filename
                restored.size = file.size
                restored.mtime = file.mtime
                restored.status = .available
                restored.needsReanalysis = false
                replace(restored)
                claimedDisk.insert(file.relativePath)
                tick(file.relativePath)
                continue
            }

            let sizeMatches = unlocated.filter { $0.contentHash == nil && $0.size == file.size && $0.mtime == file.mtime }
            if sizeMatches.count == 1, let only = sizeMatches.first, let matchIndex = unlocated.firstIndex(of: only) {
                var restored = unlocated.remove(at: matchIndex)
                restored.relativePath = file.relativePath
                restored.filename = file.filename
                restored.size = file.size
                restored.mtime = file.mtime
                restored.contentHash = newHash
                restored.status = .available
                replace(restored)
                claimedDisk.insert(file.relativePath)
                tick(file.relativePath)
                continue
            }

            let added = FootageSnapshot(
                id: UUID(),
                relativePath: file.relativePath,
                filename: file.filename,
                size: file.size,
                mtime: file.mtime,
                contentHash: newHash,
                phash: nil,
                status: .available,
                tags: [],
                userNotes: "",
                parentID: nil,
                duration: nil,
                width: nil,
                height: nil,
                capturedAt: nil,
                needsReanalysis: true
            )
            replace(added)
            claimedDisk.insert(file.relativePath)
            tick(file.relativePath)
        }

        for leftover in unlocated {
            var missing = leftover
            missing.status = .missing
            replace(missing)
        }

        let availableHashes = Dictionary(grouping: records.filter { $0.status == .available && $0.contentHash != nil }) {
            $0.contentHash!
        }
        let duplicateHashes = availableHashes.compactMap { hash, items in
            items.count > 1 ? hash : nil
        }.sorted()

        return ReconcileOutcome(records: records, hashedPaths: hashedPaths, duplicateHashes: duplicateHashes)
    }

    static func scanDisk(
        root: URL,
        fileManager: FileManager = .default,
        onProgress: ((String, Int) -> Void)? = nil
    ) -> [DiskEntry] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let rootPath = root.standardizedFileURL.path
        var entries: [DiskEntry] = []
        var lastProgressAt: TimeInterval = 0
        var lastReportedCount = -1

        func report(_ path: String, force: Bool = false) {
            guard onProgress != nil else { return }
            let now = Date().timeIntervalSince1970
            if !force, entries.count == lastReportedCount, now - lastProgressAt < 0.12 {
                return
            }
            if !force, now - lastProgressAt < 0.12, entries.count - lastReportedCount < 25 {
                return
            }
            lastProgressAt = now
            lastReportedCount = entries.count
            onProgress?(path, entries.count)
        }

        for case let url as URL in enumerator {
            let relative = relativePath(for: url, rootPath: rootPath)
            if relative == MediaConstants.rolltagDirectory || relative.hasPrefix(MediaConstants.rolltagDirectory + "/") {
                enumerator.skipDescendants()
                continue
            }
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isDirectory == true { continue }
            guard values.isRegularFile == true else { continue }
            let ext = url.pathExtension.lowercased()
            guard MediaConstants.supportedExtensions.contains(ext) else { continue }
            let size = Int64(values.fileSize ?? 0)
            let mtime = Int64(values.contentModificationDate?.timeIntervalSince1970 ?? 0)
            entries.append(DiskEntry(relativePath: relative, size: size, mtime: mtime))
            report(relative)
        }
        if let last = entries.last {
            report(last.relativePath, force: true)
        } else {
            onProgress?("", 0)
        }
        return entries
    }

    static func relativePath(for url: URL, rootPath: String) -> String {
        let path = url.path
        guard path.hasPrefix(rootPath) else { return url.lastPathComponent }
        let rest = path.dropFirst(rootPath.count)
        return rest.first == "/" ? String(rest.dropFirst()) : String(rest)
    }
}
