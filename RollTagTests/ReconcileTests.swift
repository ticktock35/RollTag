import XCTest
@testable import RollTag

final class ReconcileTests: XCTestCase {
    private let tag = TagAssignment.user(category: "mood", value: "calm")

    func testRenameKeepsIdentityAndTags() {
        let existing = [snapshot(id: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", path: "trip/old.mov", hash: "abc", tags: [tag])]
        let disk = [DiskEntry(relativePath: "trip/new.mov", size: 100, mtime: 10)]
        var hashed: [String] = []
        let outcome = ReconcileService.plan(existing: existing, disk: disk) { path in
            hashed.append(path)
            return "abc"
        }

        XCTAssertEqual(outcome.records.count, 1)
        XCTAssertEqual(outcome.records[0].relativePath, "trip/new.mov")
        XCTAssertEqual(outcome.records[0].filename, "new.mov")
        XCTAssertEqual(outcome.records[0].status, .available)
        XCTAssertEqual(outcome.records[0].tags, [tag])
        XCTAssertEqual(hashed, ["trip/new.mov"])
    }

    func testDeletedFileIsMarkedMissingAndHiddenFromSearchLater() {
        let existing = [snapshot(id: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", path: "gone.mov", hash: "abc")]
        let outcome = ReconcileService.plan(existing: existing, disk: []) { _ in
            XCTFail("missing files should not be hashed")
            return ""
        }

        XCTAssertEqual(outcome.records[0].status, .missing)
        XCTAssertEqual(outcome.records[0].relativePath, "gone.mov")
    }

    func testSameContentReturningRestoresRecord() {
        let existing = [snapshot(id: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", path: "old.mov", hash: "abc", status: .missing, tags: [tag])]
        let disk = [DiskEntry(relativePath: "archive/back.mov", size: 100, mtime: 20)]
        let outcome = ReconcileService.plan(existing: existing, disk: disk) { _ in "abc" }

        XCTAssertEqual(outcome.records[0].status, .available)
        XCTAssertEqual(outcome.records[0].relativePath, "archive/back.mov")
        XCTAssertEqual(outcome.records[0].tags, [tag])
    }

    func testContentChangeKeepsTagsAndClearsPhash() {
        let existing = [snapshot(id: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", path: "same.mov", hash: "old", phash: "1111", tags: [tag], size: 100, mtime: 10)]
        let disk = [DiskEntry(relativePath: "same.mov", size: 200, mtime: 11)]
        let outcome = ReconcileService.plan(existing: existing, disk: disk) { _ in "new-hash" }

        XCTAssertEqual(outcome.records[0].contentHash, "new-hash")
        XCTAssertNil(outcome.records[0].phash)
        XCTAssertTrue(outcome.records[0].needsReanalysis)
        XCTAssertEqual(outcome.records[0].tags, [tag])
        XCTAssertEqual(outcome.records[0].status, .available)
    }

    func testNewFileIsAdded() {
        let outcome = ReconcileService.plan(existing: [], disk: [DiskEntry(relativePath: "fresh.mov", size: 50, mtime: 1)]) { _ in "fresh" }
        XCTAssertEqual(outcome.records.count, 1)
        XCTAssertEqual(outcome.records[0].relativePath, "fresh.mov")
        XCTAssertEqual(outcome.records[0].contentHash, "fresh")
        XCTAssertTrue(outcome.records[0].tags.isEmpty)
        XCTAssertTrue(outcome.records[0].needsReanalysis)
    }

    func testSameContentAtTwoPathsIsDuplicateNotMerged() {
        let existing = [snapshot(id: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", path: "a.mov", hash: "dup")]
        let disk = [
            DiskEntry(relativePath: "a.mov", size: 100, mtime: 10),
            DiskEntry(relativePath: "copy/b.mov", size: 100, mtime: 10)
        ]
        let outcome = ReconcileService.plan(existing: existing, disk: disk) { path in
            path.hasSuffix("b.mov") || path.hasSuffix("a.mov") ? "dup" : "other"
        }

        XCTAssertEqual(outcome.records.count, 2)
        XCTAssertEqual(Set(outcome.records.map(\.status)), [.available])
        XCTAssertEqual(outcome.duplicateHashes, ["dup"])
        XCTAssertEqual(Set(outcome.records.map(\.relativePath)), ["a.mov", "copy/b.mov"])
    }

    func testPlanReportsProgressForEachDiskFile() {
        let disk = [
            DiskEntry(relativePath: "a.mov", size: 10, mtime: 1),
            DiskEntry(relativePath: "b.mov", size: 11, mtime: 2)
        ]
        var seen: [String] = []
        var last = (0, 0)
        _ = ReconcileService.plan(existing: [], disk: disk, hashOf: { _ in "h" }) { path, done, total in
            seen.append(path)
            last = (done, total)
        }
        XCTAssertEqual(last.0, 2)
        XCTAssertEqual(last.1, 2)
        XCTAssertTrue(seen.contains("a.mov"))
        XCTAssertTrue(seen.contains("b.mov"))
    }

    func testMatchingPathSizeAndMtimeSkipsHash() {
        let existing = [snapshot(id: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", path: "stable.mov", hash: "abc", size: 88, mtime: 9)]
        let disk = [DiskEntry(relativePath: "stable.mov", size: 88, mtime: 9)]
        let outcome = ReconcileService.plan(existing: existing, disk: disk) { _ in
            XCTFail("fast path must not read file contents")
            return "should-not-run"
        }
        XCTAssertTrue(outcome.hashedPaths.isEmpty)
        XCTAssertEqual(outcome.records[0].status, .available)
    }

    func testScanAcceptsPhotosAudioAndVideo() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("rolltag-scan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("DCIM"), withIntermediateDirectories: true)
        for name in ["IMG_0001.HEIC", "shot.JPEG", "pic.png", "sticker.webp", "voice.mp3", "clip.MP4", "notes.txt"] {
            try Data("x".utf8).write(to: root.appendingPathComponent("DCIM").appendingPathComponent(name))
        }
        let entries = ReconcileService.scanDisk(root: root)
        XCTAssertEqual(
            Set(entries.map(\.filename)),
            ["IMG_0001.HEIC", "shot.JPEG", "pic.png", "sticker.webp", "voice.mp3", "clip.MP4"]
        )
        XCTAssertEqual(MediaKind.of(filename: "IMG_0001.HEIC"), .image)
        XCTAssertEqual(MediaKind.of(filename: "voice.mp3"), .audio)
        XCTAssertEqual(MediaKind.of(filename: "clip.MP4"), .video)
        XCTAssertFalse(MediaKind.of(filename: "photo.jpg").canHoverPlay)
        XCTAssertTrue(MediaKind.of(filename: "a.mov").canTrim)
    }

    private func snapshot(
        id: String,
        path: String,
        hash: String?,
        phash: String? = "ph",
        status: FootageStatus = .available,
        tags: [TagAssignment] = [],
        size: Int64 = 100,
        mtime: Int64 = 10
    ) -> FootageSnapshot {
        FootageSnapshot(
            id: UUID(uuidString: id)!,
            relativePath: path,
            filename: (path as NSString).lastPathComponent,
            size: size,
            mtime: mtime,
            contentHash: hash,
            phash: phash,
            status: status,
            tags: tags,
            userNotes: "keep me",
            parentID: nil,
            duration: 12,
            width: 1920,
            height: 1080,
            capturedAt: nil,
            needsReanalysis: false
        )
    }
}
