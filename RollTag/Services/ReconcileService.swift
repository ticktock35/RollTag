import Foundation

enum ReconcileService {
    static func plan(
        existing: [FootageSnapshot],
        disk: [DiskEntry],
        hashOf: (String) -> String,
        onProgress: ((String, Int, Int) -> Void)? = nil
    ) -> ReconcileOutcome {
        var records = existing
        var hashedPaths: [String] = []
        var hashCache: [String: String] = [:]

        func hash(_ relativePath: String) -> String {
            if let cached = hashCache[relativePath] { return cached }
            hashedPaths.append(relativePath)
            let value = hashOf(relativePath)
            hashCache[relativePath] = value
            return value
        }

        func replace(_ snapshot: FootageSnapshot) {
            if let index = records.firstIndex(where: { $0.id == snapshot.id }) {
                records[index] = snapshot
            } else {
                records.append(snapshot)
            }
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
            guard var current = records.first(where: { $0.relativePath == file.relativePath }) else { continue }
            claimedDisk.insert(file.relativePath)

            let filename = file.filename
            if current.size == file.size, current.mtime == file.mtime, current.status == .available, current.contentHash != nil {
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
            records.append(added)
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
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var entries: [DiskEntry] = []
        for case let url as URL in enumerator {
            let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
            if relative.hasPrefix(MediaConstants.rolltagDirectory) {
                enumerator.skipDescendants()
                continue
            }
            onProgress?(relative, entries.count)
            let ext = url.pathExtension.lowercased()
            guard MediaConstants.supportedExtensions.contains(ext) else { continue }
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
                  values.isRegularFile == true
            else { continue }
            let size = Int64(values.fileSize ?? 0)
            let mtime = Int64(values.contentModificationDate?.timeIntervalSince1970 ?? 0)
            entries.append(DiskEntry(relativePath: relative, size: size, mtime: mtime))
            onProgress?(relative, entries.count)
        }
        return entries
    }
}
