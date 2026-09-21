import XCTest
@testable import RollTag

final class FootageFilterTests: XCTestCase {
    private let catalog = TagCatalog(categories: [
        TagCategory(id: "mood", names: ["zh-Hant": "情緒", "en": "Mood"], tags: []),
        TagCategory(id: "nature", names: ["zh-Hant": "自然", "en": "Nature"], tags: [])
    ])

    func testMissingCollectionIncludesMissingEvenWhenOffline() {
        var gone = clip()
        gone.status = .missing
        XCTAssertTrue(FootageFilter.include(footage: gone, isOnline: true, selection: .collection(.missing), isDuplicate: false))
        XCTAssertTrue(FootageFilter.include(footage: gone, isOnline: false, selection: .collection(.missing), isDuplicate: false))
        XCTAssertFalse(FootageFilter.include(footage: gone, isOnline: true, selection: .collection(.all), isDuplicate: false))
    }

    func testTaggedCollectionOnlyShowsTaggedAvailableFootage() {
        let tagged = clip(tags: [.user(category: "mood", value: "calm")])
        let bare = clip(id: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB", tags: [])
        XCTAssertTrue(FootageFilter.include(footage: tagged, isOnline: true, selection: .collection(.tagged), isDuplicate: false))
        XCTAssertFalse(FootageFilter.include(footage: bare, isOnline: true, selection: .collection(.tagged), isDuplicate: false))
        XCTAssertTrue(FootageFilter.include(footage: bare, isOnline: true, selection: .collection(.untagged), isDuplicate: false))
    }

    func testExistingTagsAppearUnderTheirCategory() {
        let mood = clip(tags: [.user(category: "mood", value: "calm")])
        let custom = clip(id: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB", tags: [.custom("測試")!])
        XCTAssertTrue(FootageFilter.include(footage: mood, isOnline: true, selection: .tagCategory("mood"), isDuplicate: false))
        XCTAssertFalse(FootageFilter.include(footage: custom, isOnline: true, selection: .tagCategory("mood"), isDuplicate: false))
        XCTAssertTrue(FootageFilter.include(footage: custom, isOnline: true, selection: .tagCategory(TagAssignment.customCategory), isDuplicate: false))
    }

    func testPopulatedCategoriesIncludeUsedPresetAndCustom() {
        let footage = [
            clip(tags: [.user(category: "mood", value: "calm")]),
            clip(id: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB", tags: [.custom("測試")!])
        ]
        let categories = FootageFilter.populatedCategories(
            from: footage,
            catalog: catalog,
            locale: "zh-Hant",
            customTitle: "自訂"
        )
        XCTAssertEqual(categories.map(\.id), ["mood", "custom"])
        XCTAssertEqual(categories.first?.title, "情緒")
        XCTAssertEqual(categories.last?.title, "自訂")
    }

    func testUnusedCategoryDoesNotAppear() {
        let footage = [clip(tags: [.user(category: "mood", value: "calm")])]
        let categories = FootageFilter.populatedCategories(
            from: footage,
            catalog: catalog,
            locale: "en",
            customTitle: "Custom"
        )
        XCTAssertEqual(categories.map(\.id), ["mood"])
    }

    func testWarehouseFolderIncludesDescendantsOnly() {
        let warehouse = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let inJohor = clip(relativePath: "malaysia/johor/clubmed/a.mov")
        let inKL = clip(id: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB", relativePath: "malaysia/kl/b.mov")
        let siblingPrefix = clip(id: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD", relativePath: "malaysia備份/c.mov")
        let rootFile = clip(id: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE", relativePath: "root.mov")
        let folder = SidebarSelection.warehouseFolder(warehouse, "malaysia")
        XCTAssertTrue(FootageFilter.include(footage: inJohor, isOnline: true, selection: folder, isDuplicate: false))
        XCTAssertTrue(FootageFilter.include(footage: inKL, isOnline: true, selection: folder, isDuplicate: false))
        XCTAssertFalse(FootageFilter.include(footage: siblingPrefix, isOnline: true, selection: folder, isDuplicate: false))
        XCTAssertFalse(FootageFilter.include(footage: rootFile, isOnline: true, selection: folder, isDuplicate: false))
        XCTAssertTrue(FootageFilter.include(footage: rootFile, isOnline: true, selection: .warehouse(warehouse), isDuplicate: false))
    }

    func testWarehouseFolderDoesNotShowOfflineOrMissing() {
        let warehouse = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        var missing = clip(relativePath: "malaysia/gone.mov")
        missing.status = .missing
        let folder = SidebarSelection.warehouseFolder(warehouse, "malaysia")
        XCTAssertFalse(FootageFilter.include(footage: missing, isOnline: true, selection: folder, isDuplicate: false))
        XCTAssertFalse(FootageFilter.include(footage: clip(relativePath: "malaysia/a.mov"), isOnline: false, selection: folder, isDuplicate: false))
    }

    func testWorkFoldersKeepUntaggedAndDuplicatesInsideThoseDirectories() {
        let warehouse = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let johor = clip(relativePath: "malaysia/johor/a.mov")
        let kl = clip(id: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB", relativePath: "malaysia/kl/b.mov")
        let scopes: Set<FolderRef> = [
            FolderRef(warehouseID: warehouse, relativePath: "malaysia/johor")
        ]
        XCTAssertTrue(
            FootageFilter.include(
                footage: johor,
                isOnline: true,
                selection: .collection(.untagged),
                isDuplicate: false,
                folderScopes: scopes
            )
        )
        XCTAssertFalse(
            FootageFilter.include(
                footage: kl,
                isOnline: true,
                selection: .collection(.untagged),
                isDuplicate: false,
                folderScopes: scopes
            )
        )
        XCTAssertTrue(
            FootageFilter.include(
                footage: johor,
                isOnline: true,
                selection: .collection(.duplicates),
                isDuplicate: true,
                folderScopes: scopes
            )
        )
        XCTAssertFalse(
            FootageFilter.include(
                footage: kl,
                isOnline: true,
                selection: .collection(.duplicates),
                isDuplicate: true,
                folderScopes: scopes
            )
        )
        XCTAssertTrue(
            FootageFilter.duplicateGroup(
                [johor.id, kl.id],
                members: [johor, kl],
                intersects: scopes
            )
        )
        XCTAssertFalse(
            FootageFilter.duplicateGroup(
                [kl.id],
                members: [kl],
                intersects: scopes
            )
        )
    }

    func testMultipleWorkFoldersAreAUnion() {
        let warehouse = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let johor = clip(relativePath: "malaysia/johor/a.mov")
        let kl = clip(id: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB", relativePath: "malaysia/kl/b.mov")
        let root = clip(id: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD", relativePath: "root.mov")
        let scopes: Set<FolderRef> = [
            FolderRef(warehouseID: warehouse, relativePath: "malaysia/johor"),
            FolderRef(warehouseID: warehouse, relativePath: "malaysia/kl")
        ]
        XCTAssertTrue(FootageFilter.include(footage: johor, isOnline: true, selection: .collection(.all), isDuplicate: false, folderScopes: scopes))
        XCTAssertTrue(FootageFilter.include(footage: kl, isOnline: true, selection: .collection(.all), isDuplicate: false, folderScopes: scopes))
        XCTAssertFalse(FootageFilter.include(footage: root, isOnline: true, selection: .collection(.all), isDuplicate: false, folderScopes: scopes))
    }

    func testDuplicateIndexUsesMemberIDsAndFolderScope() {
        let warehouseID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let johor = clip(relativePath: "malaysia/johor/a.mov")
        let backup = clip(id: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB", relativePath: "backup/a.mov")
        let other = clip(id: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD", relativePath: "other/b.mov")
        let otherTwin = clip(id: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE", relativePath: "other/b-copy.mov")
        let warehouse = WarehouseRuntime(
            preference: WarehousePreference(id: warehouseID, name: "W", path: "/tmp", bookmark: nil),
            isOnline: true,
            isReconciling: false,
            footage: [johor, backup, other, otherTwin],
            groups: [
                DuplicateGroup(
                    id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                    contentHash: "same-a",
                    resolution: .unresolved,
                    memberIDs: [johor.id, backup.id]
                ),
                DuplicateGroup(
                    id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                    contentHash: "same-b",
                    resolution: .unresolved,
                    memberIDs: [other.id, otherTwin.id]
                )
            ]
        )
        let scoped = DuplicateIndex.resolve(
            warehouses: [warehouse],
            scopes: [FolderRef(warehouseID: warehouseID, relativePath: "malaysia/johor")]
        )
        XCTAssertEqual(scoped.map(\.group.contentHash), ["same-a"])
        XCTAssertEqual(Set(scoped[0].members.map(\.id)), [johor.id, backup.id])
        let all = DuplicateIndex.resolve(warehouses: [warehouse], scopes: [])
        XCTAssertEqual(Set(all.map(\.group.contentHash)), ["same-a", "same-b"])
    }

    func testDuplicateIndexCountsOnlyUnresolvedGroups() {
        let warehouseID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let keep = clip(relativePath: "keep.mov")
        let copy = clip(id: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB", relativePath: "copy.mov")
        let left = clip(id: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD", relativePath: "left.mov")
        let right = clip(id: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE", relativePath: "right.mov")
        let warehouse = WarehouseRuntime(
            preference: WarehousePreference(id: warehouseID, name: "W", path: "/tmp", bookmark: nil),
            isOnline: true,
            isReconciling: false,
            footage: [keep, copy, left, right],
            groups: [
                DuplicateGroup(
                    id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                    contentHash: "pending",
                    resolution: .unresolved,
                    memberIDs: [keep.id, copy.id]
                ),
                DuplicateGroup(
                    id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                    contentHash: "kept-apart",
                    resolution: .keepSeparate,
                    memberIDs: [left.id, right.id]
                )
            ]
        )
        XCTAssertEqual(DuplicateIndex.resolve(warehouses: [warehouse], scopes: []).count, 1)
        XCTAssertEqual(DuplicateIndex.resolve(warehouses: [warehouse], scopes: []).first?.group.contentHash, "pending")
    }

    func testSidebarCollectionCountsFollowTagsMissingOfflineAndFolderScope() {
        let warehouseID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let tagged = clip(relativePath: "malaysia/a.mov", tags: [.user(category: "mood", value: "calm")])
        let untagged = clip(id: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB", relativePath: "malaysia/b.mov")
        let outside = clip(id: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD", relativePath: "other/c.mov")
        var missing = clip(id: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE", relativePath: "malaysia/gone.mov")
        missing.status = .missing
        let warehouse = WarehouseRuntime(
            preference: WarehousePreference(id: warehouseID, name: "W", path: "/tmp", bookmark: nil),
            isOnline: true,
            isReconciling: false,
            footage: [tagged, untagged, outside, missing],
            groups: []
        )
        let all = FootageFilter.collectionCounts(warehouses: [warehouse], scopes: [], duplicateGroups: 7)
        XCTAssertEqual(all.all, 3)
        XCTAssertEqual(all.tagged, 1)
        XCTAssertEqual(all.untagged, 2)
        XCTAssertEqual(all.missing, 1)
        XCTAssertEqual(all.duplicates, 7)
        XCTAssertEqual(all.value(for: .untagged), 2)

        let scoped = FootageFilter.collectionCounts(
            warehouses: [warehouse],
            scopes: [FolderRef(warehouseID: warehouseID, relativePath: "malaysia")],
            duplicateGroups: 1
        )
        XCTAssertEqual(scoped.all, 2)
        XCTAssertEqual(scoped.tagged, 1)
        XCTAssertEqual(scoped.untagged, 1)
        XCTAssertEqual(scoped.missing, 1)

        let offline = WarehouseRuntime(
            preference: WarehousePreference(id: warehouseID, name: "W", path: "/tmp", bookmark: nil),
            isOnline: false,
            isReconciling: false,
            footage: [tagged, missing],
            groups: []
        )
        let off = FootageFilter.collectionCounts(warehouses: [offline], scopes: [], duplicateGroups: 0)
        XCTAssertEqual(off.all, 0)
        XCTAssertEqual(off.tagged, 0)
        XCTAssertEqual(off.untagged, 0)
        XCTAssertEqual(off.missing, 1)
    }

    func testFolderTreeFollowsIndexedDirectoriesAndHidesDotFolders() {
        let warehouse = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let footage = [
            clip(relativePath: "malaysia/johor/clubmed/a.mov"),
            clip(id: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB", relativePath: "malaysia/kl/b.mov"),
            clip(id: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD", relativePath: "root.mov"),
            clip(id: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE", relativePath: ".rolltag/trimmed/cut.mov")
        ]
        let tree = WarehouseFolderTree.nodes(warehouseID: warehouse, from: footage)
        XCTAssertEqual(tree.map(\.relativePath), ["malaysia"])
        XCTAssertEqual(tree[0].children?.map(\.relativePath), ["malaysia/johor", "malaysia/kl"])
        XCTAssertEqual(tree[0].children?.first?.children?.map(\.relativePath), ["malaysia/johor/clubmed"])
        XCTAssertTrue(WarehouseFolderTree.contains(directoryPath: "malaysia/johor", folder: "malaysia"))
        XCTAssertFalse(WarehouseFolderTree.contains(directoryPath: "malaysia備份", folder: "malaysia"))
    }

    func testTinyVideoIsTooSmallToPreview() {
        var tiny = clip(tags: [])
        tiny.size = 1024
        tiny.filename = "DJI_0029_D.MP4"
        tiny.relativePath = "DJI_0029_D.MP4"
        XCTAssertTrue(tiny.isTooSmallToPreview)

        var real = tiny
        real.size = 12_000_000
        XCTAssertFalse(real.isTooSmallToPreview)
    }

    private func clip(
        id: String = "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
        relativePath: String = "clip.mov",
        tags: [TagAssignment] = []
    ) -> Footage {
        Footage(
            id: UUID(uuidString: id)!,
            warehouseID: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            relativePath: relativePath,
            filename: (relativePath as NSString).lastPathComponent,
            size: 1,
            mtime: 1,
            contentHash: "h",
            phash: nil,
            status: .available,
            duration: 1,
            width: 10,
            height: 10,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            parentID: nil,
            userNotes: "",
            tags: tags,
            capturedAt: nil
        )
    }
}
