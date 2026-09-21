import AppKit
import Foundation
import Observation

struct WarehouseRuntime: Identifiable, Hashable {
    var preference: WarehousePreference
    var isOnline: Bool
    var isReconciling: Bool
    var footage: [Footage]
    var groups: [DuplicateGroup]
    var footageByID: [UUID: Footage]
    var folderNodes: [WarehouseFolderNode]

    var id: UUID { preference.id }

    init(
        preference: WarehousePreference,
        isOnline: Bool,
        isReconciling: Bool,
        footage: [Footage],
        groups: [DuplicateGroup]
    ) {
        self.preference = preference
        self.isOnline = isOnline
        self.isReconciling = isReconciling
        self.footage = footage
        self.groups = groups
        self.footageByID = Dictionary(uniqueKeysWithValues: footage.map { ($0.id, $0) })
        self.folderNodes = WarehouseFolderTree.nodes(warehouseID: preference.id, from: footage)
    }
}

struct DuplicateKeepRequest: Equatable {
    var warehouseID: UUID
    var group: DuplicateGroup
    var keeperID: UUID
    var keeperName: String
    var otherCount: Int
}

@MainActor
@Observable
final class AppModel {
    var preference = PreferenceFile.empty
    var warehouses: [WarehouseRuntime] = []
    var sidebarSelection: SidebarSelection = .collection(.all) {
        didSet {
            syncWorkFolders(from: sidebarSelection)
            rebuildVisibleResults()
        }
    }
    var workFolders: Set<FolderRef> = [] {
        didSet { rebuildVisibleResults() }
    }
    var searchText = "" {
        didSet { rebuildVisibleResults() }
    }
    var librarySort: LibrarySort = .filename {
        didSet { rebuildVisibleResults() }
    }
    var sortAscending = true {
        didSet { rebuildVisibleResults() }
    }
    private(set) var visibleResults: [ScoredFootage] = []
    private(set) var scopedDuplicateGroups: [ResolvedDuplicateGroup] = []
    var libraryEpoch = 0
    var thumbRefreshToken = 0
    var selectedIDs: Set<UUID> = []
    var expandedTagCategory: String?
    var statusMessage = ""
    var isBusy = false
    var showDuplicates = false
    var showShortcuts = false
    var showSettings = false
    var scanProgress: ScanProgress?
    var focusedFootageID: UUID?
    var trimSession: TrimSession?
    var duplicatesKeyboardActive = 0
    var duplicateSelectedGroupID: UUID?
    var duplicatePendingDelete: DuplicateKeepRequest?
    let playback = PreviewPlayback()

    let catalog: TagCatalog

    var localeID: String { TagCatalogLoader.localeID() }

    private let store: PreferenceStore
    private let sidecar = SidecarClient()
    private let volumeMonitor = VolumeMonitor()
    private var databases: [UUID: WarehouseDatabase] = [:]
    private var lastProgressPublish: TimeInterval = 0
    private var keyMonitor: Any?
    private var fullscreenObserver: NSObjectProtocol?

    init(store: PreferenceStore = PreferenceStore(), catalog: TagCatalog = TagCatalogLoader.load()) {
        self.store = store
        self.catalog = catalog
    }

    func selectLibrarySort(_ sort: LibrarySort) {
        if librarySort == sort {
            sortAscending.toggle()
        } else {
            librarySort = sort
            sortAscending = sort.defaultAscending
        }
    }

    var selectedFootage: [Footage] {
        let all = warehouses.flatMap(\.footage)
        return all.filter { selectedIDs.contains($0.id) }
    }

    var focusedFootage: Footage? {
        let all = warehouses.flatMap(\.footage)
        if let focusedFootageID, selectedIDs.contains(focusedFootageID),
           let item = all.first(where: { $0.id == focusedFootageID }) {
            return item
        }
        return selectedFootage.first
    }

    var focusedMedia: PreviewMedia? {
        guard let footage = focusedFootage,
              let warehouse = warehouses.first(where: { $0.id == footage.warehouseID }),
              warehouse.isOnline
        else { return nil }
        return PreviewMedia(
            id: footage.id,
            url: footage.absoluteURL(warehouseRoot: warehouse.preference.url),
            kind: footage.mediaKind,
            filename: footage.filename,
            width: footage.width,
            height: footage.height,
            duration: footage.duration,
            fileSize: footage.size
        )
    }

    var canBeginTrim: Bool {
        guard selectedFootage.count == 1, let footage = focusedFootage, footage.mediaKind.canTrim,
              !footage.isTooSmallToPreview else { return false }
        return warehouses.first(where: { $0.id == footage.warehouseID })?.isOnline == true
    }

    func footage(id: UUID) -> Footage? {
        warehouses.flatMap(\.footage).first(where: { $0.id == id })
    }

    func onlineRoot(for footageID: UUID) -> URL? {
        guard let footage = self.footage(id: footageID),
              let warehouse = warehouses.first(where: { $0.id == footage.warehouseID }),
              warehouse.isOnline
        else { return nil }
        return warehouse.preference.url
    }

    func presentFocusedMedia() {
        playback.present(focusedMedia)
    }

    func beginTrim() {
        guard canBeginTrim, let footage = focusedFootage,
              let warehouse = warehouses.first(where: { $0.id == footage.warehouseID })
        else { return }
        trimSession = TrimSession(
            footageID: footage.id,
            warehouseID: footage.warehouseID,
            url: footage.absoluteURL(warehouseRoot: warehouse.preference.url),
            filename: footage.filename
        )
    }

    func closeTrim() {
        trimSession = nil
    }

    func proposeDuplicateKeepLeft() {
        guard let pair = currentDuplicatePair() else { return }
        let members = duplicateMembers(pair)
        guard let keeper = members.first else { return }
        proposeDuplicateKeep(warehouseID: pair.0.id, group: pair.1, keeperID: keeper.id)
    }

    func proposeDuplicateKeepRight() {
        guard let pair = currentDuplicatePair() else { return }
        let members = duplicateMembers(pair)
        guard let keeper = members.last else { return }
        proposeDuplicateKeep(warehouseID: pair.0.id, group: pair.1, keeperID: keeper.id)
    }

    func proposeDuplicateKeep(warehouseID: UUID, group: DuplicateGroup, keeperID: UUID) {
        guard duplicatePendingDelete == nil else { return }
        guard let warehouse = warehouses.first(where: { $0.id == warehouseID }) else { return }
        let members = duplicateMembers((warehouse, group))
        guard let keeper = members.first(where: { $0.id == keeperID }) ?? members.first else { return }
        duplicateSelectedGroupID = group.id
        selectedIDs = [keeper.id]
        focusedFootageID = keeper.id
        presentFocusedMedia()
        duplicatePendingDelete = DuplicateKeepRequest(
            warehouseID: warehouse.id,
            group: group,
            keeperID: keeper.id,
            keeperName: keeper.filename,
            otherCount: max(0, members.count - 1)
        )
    }

    func keepAllCurrentDuplicate() {
        guard duplicatePendingDelete == nil, let pair = currentDuplicatePair() else { return }
        let members = duplicateMembers(pair)
        guard let first = members.first else { return }
        resolveDuplicates(
            group: pair.1,
            warehouseID: pair.0.id,
            keeperID: first.id,
            unionTags: false,
            keepSeparate: true
        )
    }

    func confirmDuplicateTrash() {
        guard let pending = duplicatePendingDelete else { return }
        resolveDuplicates(
            group: pending.group,
            warehouseID: pending.warehouseID,
            keeperID: pending.keeperID,
            unionTags: true,
            keepSeparate: false,
            deleteOthers: true
        )
        duplicatePendingDelete = nil
    }

    func cancelDuplicateTrash() {
        duplicatePendingDelete = nil
    }

    private func currentDuplicatePair() -> (WarehouseRuntime, DuplicateGroup)? {
        if let resolved = resolvedDuplicateGroup(id: duplicateSelectedGroupID)
            ?? scopedDuplicateGroups.first,
           let warehouse = warehouses.first(where: { $0.id == resolved.warehouseID }) {
            return (warehouse, resolved.group)
        }
        return nil
    }

    private func resolvedDuplicateGroup(id: UUID?) -> ResolvedDuplicateGroup? {
        guard let id else { return nil }
        return scopedDuplicateGroups.first(where: { $0.id == id })
    }

    private func duplicateMembers(_ pair: (WarehouseRuntime, DuplicateGroup)) -> [Footage] {
        if let resolved = scopedDuplicateGroups.first(where: { $0.id == pair.1.id }) {
            return resolved.members
        }
        return pair.1.memberIDs.compactMap { pair.0.footageByID[$0] }
            .sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }

    var unresolvedDuplicateGroups: [(WarehouseRuntime, DuplicateGroup)] {
        scopedDuplicateGroups.compactMap { item in
            guard let warehouse = warehouses.first(where: { $0.id == item.warehouseID }) else { return nil }
            return (warehouse, item.group)
        }
    }

    func selectDuplicateMember(_ id: UUID) {
        selectedIDs = [id]
        focusedFootageID = id
    }

    var workFolderNames: [String] {
        workFolders
            .sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
            .map(\.folderName)
    }

    var workFolderSummary: String {
        workFolderNames.joined(separator: "、")
    }

    func isWorkFolder(_ ref: FolderRef) -> Bool {
        workFolders.contains(ref)
    }

    func toggleWorkFolder(_ ref: FolderRef) {
        if workFolders.contains(ref) {
            workFolders.remove(ref)
        } else {
            workFolders.insert(ref)
        }
    }

    func clearWorkFolders() {
        workFolders = []
        if case .warehouseFolder(let id, _) = sidebarSelection {
            sidebarSelection = .warehouse(id)
        }
    }

    private func syncWorkFolders(from selection: SidebarSelection) {
        switch selection {
        case .warehouseFolder(let id, let path):
            let ref = FolderRef(warehouseID: id, relativePath: path)
            if !workFolders.contains(ref) {
                workFolders = [ref]
            }
        case .warehouse:
            workFolders = []
        default:
            break
        }
    }

    func start() {
        sidecar.start()
        do {
            preference = try store.load()
        } catch {
            preference = .empty
            statusMessage = error.localizedDescription
        }
        refreshOnlineState()
        volumeMonitor.start { [weak self] in
            Task { @MainActor in
                self?.refreshOnlineState()
                await self?.reconcileOnlineWarehouses()
            }
        }
        Task {
            await reconcileOnlineWarehouses()
        }
        installPlaybackKeys()
    }

    func stop() {
        volumeMonitor.stop()
        sidecar.stop()
        removePlaybackKeys()
        playback.unload()
        trimSession = nil
    }

    func refreshOnlineState() {
        warehouses = preference.warehouses.map { item in
            let existing = warehouses.first(where: { $0.id == item.id })
            let online = store.isOnline(item)
            if online { store.startAccessing(item) }
            return WarehouseRuntime(
                preference: item,
                isOnline: online,
                isReconciling: existing?.isReconciling ?? false,
                footage: online ? (existing?.footage ?? []) : (existing?.footage ?? []),
                groups: existing?.groups ?? []
            )
        }
    }

    func addWarehouse(url: URL) {
        let bookmark = store.bookmark(for: url)
        preference = store.addWarehouse(named: url.lastPathComponent, path: url.path, bookmark: bookmark, to: preference)
        persistPreference()
        refreshOnlineState()
        Task { await reconcileOnlineWarehouses() }
    }

    func renameWarehouse(id: UUID, name: String) {
        preference = store.updateWarehouse(id: id, name: name, in: preference)
        persistPreference()
        refreshOnlineState()
    }

    func updateWarehouse(id: UUID, name: String?, path: String?) {
        var bookmark: Data?
        if let path {
            bookmark = store.bookmark(for: URL(fileURLWithPath: path))
        }
        preference = store.updateWarehouse(id: id, name: name, path: path, bookmark: bookmark, in: preference)
        persistPreference()
        refreshOnlineState()
        if path != nil {
            Task { await reconcileOnlineWarehouses() }
        }
    }

    func selectAIProvider(_ provider: AIProvider?) {
        preference = store.updateAI(selectedProvider: provider, in: preference)
        persistPreference()
    }

    func updateAIKey(provider: AIProvider, apiKey: String, model: String? = nil) {
        preference = store.updateAIKey(provider: provider, apiKey: apiKey, model: model, in: preference)
        persistPreference()
    }

    func updateSkipImplausibleCaptureDates(_ skip: Bool) {
        preference = store.updateSkipImplausibleCaptureDates(skip, in: preference)
        persistPreference()
    }

    func removeWarehouse(id: UUID) {
        preference = store.removeWarehouse(id: id, from: preference)
        databases[id] = nil
        persistPreference()
        refreshOnlineState()
    }

    func chooseWarehouseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = String(localized: "warehouse.add")
        if panel.runModal() == .OK, let url = panel.url {
            addWarehouse(url: url)
        }
    }

    var populatedTagCategories: [BrowsableTagCategory] {
        let footage = warehouses.filter(\.isOnline).flatMap(\.footage)
        return FootageFilter.populatedCategories(
            from: footage,
            catalog: catalog,
            locale: localeID,
            customTitle: String(localized: "tags.customCategory")
        )
    }

    var knownCustomTags: [TagAssignment] {
        let tags = warehouses.flatMap(\.footage).flatMap(\.tags).filter(\.isCustom)
        return TagAssignment.uniqued(tags).sorted { $0.value.localizedStandardCompare($1.value) == .orderedAscending }
    }

    var showsAITagging: Bool {
        preference.ai.taggingRoute() != nil && selectedFootage.contains(where: \.canAITag)
    }

    var canTagWithAI: Bool {
        showsAITagging && !isBusy
    }

    func addTags(_ tags: [TagAssignment]) {
        applyToSelection { db, ids in
            try db.addTags(tags, to: ids)
        }
    }

    func tagSelectedWithAI() {
        Task { await tagWithAI(ids: selectedFootage.map(\.id)) }
    }

    func tagWithAI(ids: [UUID]) async {
        guard !ids.isEmpty, !isBusy else { return }
        let routes = preference.ai.taggingRoutes()
        guard !routes.isEmpty else {
            statusMessage = String(localized: "ai.missingKey")
            return
        }

        if !sidecar.isRunning {
            sidecar.start()
        }

        isBusy = true
        defer {
            isBusy = false
            if scanProgress?.phase == .tagging {
                scanProgress = nil
            }
        }

        let catalogPayload = AITagSuggester.catalogPayload(
            catalog: catalog,
            locale: localeID,
            customValues: knownCustomTags.map(\.value)
        )
        let customValues = Set(knownCustomTags.map(\.value))
        let items = warehouses.flatMap(\.footage).filter { ids.contains($0.id) }
        var tagged = 0
        var failed = 0
        var skipped = 0
        var lastError = ""

        for (index, footage) in items.enumerated() {
            publishProgress(
                ScanProgress(
                    warehouseName: String(localized: "ai.tag"),
                    warehouseID: footage.warehouseID,
                    phase: .tagging,
                    currentFile: footage.filename,
                    completed: index,
                    total: items.count
                ),
                force: true
            )

            guard footage.canAITag else {
                skipped += 1
                continue
            }

            guard let warehouse = warehouses.first(where: { $0.id == footage.warehouseID }),
                  warehouse.isOnline
            else {
                failed += 1
                continue
            }

            let url = footage.absoluteURL(warehouseRoot: warehouse.preference.url)
            let frames = await FrameExtractor.jpegStills(url: url)
            guard !frames.isEmpty else {
                skipped += 1
                lastError = String(localized: "ai.noFrames")
                continue
            }

            do {
                let live = await MediaMetadata.read(
                    url: url,
                    skipImplausibleHeader: preference.ai.skipImplausibleCaptureDates
                )
                let context = AITagSuggester.contextPayload(
                    footage: footage,
                    warehouseName: warehouse.preference.name,
                    live: live
                )
                let payload = try await suggestWithFallback(
                    routes: routes,
                    frames: frames,
                    catalog: catalogPayload,
                    context: context
                )
                let warehouseCustoms = warehouse.footage.flatMap(\.tags).filter(\.isCustom).map(\.value)
                let pathTags = PathTagMatcher.assignments(
                    relativePath: footage.relativePath,
                    catalog: catalog,
                    customValues: warehouseCustoms
                )
                let aiTags = AITagSuggester.assignments(
                    from: payload,
                    catalog: catalog,
                    customValues: customValues
                )
                let incoming = TagAssignment.uniqued(pathTags + aiTags)
                let existingByKey = Dictionary(
                    footage.tags.map { ($0.identityKey, $0) },
                    uniquingKeysWith: { TagAssignment.sourceRank($0.source) <= TagAssignment.sourceRank($1.source) ? $0 : $1 }
                )
                let novel = incoming.filter { tag in
                    guard let current = existingByKey[tag.identityKey] else { return true }
                    return TagAssignment.sourceRank(tag.source) < TagAssignment.sourceRank(current.source)
                }
                if !novel.isEmpty, let db = databases[footage.warehouseID] {
                    try db.addTags(novel, to: [footage.id])
                }
                tagged += 1
            } catch {
                failed += 1
                lastError = error.localizedDescription
            }
        }

        reloadFootage()
        statusMessage = aiStatusMessage(
            total: items.count,
            tagged: tagged,
            skipped: skipped,
            failed: failed,
            lastError: lastError
        )
    }

    private func aiStatusMessage(total: Int, tagged: Int, skipped: Int, failed: Int, lastError: String) -> String {
        if total == 1 {
            if tagged == 1 { return String(localized: "ai.doneOne") }
            if skipped == 1 {
                return lastError.isEmpty ? String(localized: "ai.skipped") : lastError
            }
            return lastError.isEmpty ? String(localized: "ai.failed") : lastError
        }
        if skipped == 0 {
            return String(format: String(localized: "ai.done"), locale: .current, tagged, failed)
        }
        return String(format: String(localized: "ai.doneSkipped"), locale: .current, tagged, skipped, failed)
    }

    private func suggestWithFallback(
        routes: [AITaggingRoute],
        frames: [Data],
        catalog: [String: Any],
        context: [String: Any]
    ) async throws -> [String: Any] {
        var lastError: Error = SidecarError.unavailable
        for route in routes {
            do {
                return try await sidecar.suggestTags(
                    provider: route.provider,
                    apiKey: route.apiKey,
                    model: route.model,
                    frames: frames,
                    catalog: catalog,
                    context: context
                )
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    @discardableResult
    func addCustomTags(from raw: String) -> Bool {
        let tags = TagAssignment.customs(from: raw)
        guard !tags.isEmpty else { return false }
        addTags(tags)
        return true
    }

    func removeTags(_ tags: [TagAssignment]) {
        applyToSelection { db, ids in
            try db.removeTags(tags, from: ids)
        }
    }

    func updateNotes(_ notes: String, for id: UUID) {
        guard let db = database(forFootage: id) else { return }
        try? db.updateNotes(id: id, notes: notes)
        reloadFootage()
    }

    func resolveDuplicates(
        group: DuplicateGroup,
        warehouseID: UUID,
        keeperID: UUID,
        unionTags: Bool,
        keepSeparate: Bool,
        deleteOthers: Bool = false
    ) {
        guard let db = databases[warehouseID], let warehouse = warehouses.first(where: { $0.id == warehouseID }) else { return }
        let members = group.memberIDs.compactMap { warehouse.footageByID[$0] }
        let others = members.filter { $0.id != keeperID }
        do {
            if keepSeparate {
                try db.setResolution(groupID: group.id, resolution: .keepSeparate)
            } else {
                try db.mergeMetadata(keeperID: keeperID, from: others, unionTags: unionTags)
                if deleteOthers {
                    var failed: [String] = []
                    for other in others {
                        let url = other.absoluteURL(warehouseRoot: warehouse.preference.url)
                        do {
                            if FileManager.default.fileExists(atPath: url.path) {
                                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                            }
                            let thumb = ThumbnailService.thumbnailFileURL(
                                warehouseRoot: warehouse.preference.url,
                                footageID: other.id
                            )
                            try? FileManager.default.removeItem(at: thumb)
                            try db.removeFootage(id: other.id)
                        } catch {
                            failed.append(other.filename)
                        }
                    }
                    if !failed.isEmpty {
                        statusMessage = String(
                            format: String(localized: "duplicates.deleteFailed"),
                            locale: .current,
                            failed.joined(separator: "、")
                        )
                    }
                    try db.deleteDuplicateGroup(id: group.id)
                } else {
                    try db.setResolution(groupID: group.id, resolution: .merged)
                }
            }
            reloadFootage()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func trimSelected(start: Double, end: Double) async {
        let id = trimSession?.footageID ?? focusedFootage?.id
        guard let id else { return }
        await exportTrim(footageID: id, start: start, end: end)
    }

    func exportTrim(footageID: UUID, start: Double, end: Double) async {
        guard let footage = footage(id: footageID) else { return }
        guard let warehouse = warehouses.first(where: { $0.id == footage.warehouseID }), warehouse.isOnline else { return }
        let source = footage.absoluteURL(warehouseRoot: warehouse.preference.url)
        let folder = warehouse.preference.url
            .appendingPathComponent(MediaConstants.rolltagDirectory)
            .appendingPathComponent(MediaConstants.trimmedDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970)
        let destination = folder.appendingPathComponent("\(footage.filename.removingExtension())_trim_\(stamp).mp4")
        isBusy = true
        do {
            try await TrimService.exportClip(source: source, destination: destination, start: start, end: end)
            await reconcile(warehouseID: footage.warehouseID)
            if var created = warehouses.first(where: { $0.id == footage.warehouseID })?.footage.first(where: {
                $0.relativePath.hasSuffix(destination.lastPathComponent)
            }) {
                created.parentID = footage.id
                if let db = databases[footage.warehouseID] {
                    try? db.update(created.snapshot())
                    reloadFootage()
                }
                selectedIDs = [created.id]
                focusedFootageID = created.id
                presentFocusedMedia()
            }
            trimSession = nil
        } catch {
            statusMessage = error.localizedDescription
        }
        isBusy = false
    }

    func selectSingle(_ id: UUID, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) {
            if selectedIDs.contains(id) {
                selectedIDs.remove(id)
                if focusedFootageID == id {
                    focusedFootageID = selectedIDs.first
                }
            } else {
                selectedIDs.insert(id)
                focusedFootageID = id
            }
        } else if modifiers.contains(.shift), let last = focusedFootageID ?? selectedIDs.first {
            let ids = visibleResults.map(\.id)
            guard let from = ids.firstIndex(of: last), let to = ids.firstIndex(of: id) else {
                selectedIDs = [id]
                focusedFootageID = id
                return
            }
            let range = from <= to ? ids[from...to] : ids[to...from]
            selectedIDs = Set(range)
            focusedFootageID = id
        } else {
            selectedIDs = [id]
            focusedFootageID = id
        }
        presentFocusedMedia()
    }

    func selectAllVisible() {
        selectedIDs = Set(visibleResults.map(\.id))
        if let focusedFootageID, selectedIDs.contains(focusedFootageID) { return }
        focusedFootageID = visibleResults.first?.id
        presentFocusedMedia()
    }

    func clearSelection() {
        selectedIDs = []
        focusedFootageID = nil
        playback.present(nil)
    }

    func exitFullscreenOrClearSelection() {
        if playback.isFullscreen {
            playback.exitFullscreen()
        } else {
            clearSelection()
        }
    }

    func revealInFinder(_ footage: Footage) {
        guard let warehouse = warehouses.first(where: { $0.id == footage.warehouseID }), warehouse.isOnline else { return }
        NSWorkspace.shared.activateFileViewerSelecting([footage.absoluteURL(warehouseRoot: warehouse.preference.url)])
    }

    func persistPreference() {
        do {
            try store.save(preference)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func reconcileOnlineWarehouses() async {
        for warehouse in preference.warehouses where store.isOnline(warehouse) {
            await reconcile(warehouseID: warehouse.id)
        }
        refreshOnlineState()
        reloadFootage()
    }

    private func reconcile(warehouseID: UUID) async {
        guard let item = preference.warehouses.first(where: { $0.id == warehouseID }) else { return }
        guard store.isOnline(item) else { return }
        setReconciling(warehouseID, true)
        ThumbnailService.deferGeneration = true
        publishProgress(
            ScanProgress(
                warehouseName: item.name,
                warehouseID: item.id,
                phase: .scanning,
                currentFile: item.path,
                completed: 0,
                total: 0
            ),
            force: true
        )
        do {
            let db = try openDatabase(for: item)
            let existing = try db.allFootage().map { $0.snapshot() }
            let root = item.url
            let warehouseName = item.name

            let disk = await scanDiskOffMain(root: root, warehouseID: warehouseID, warehouseName: warehouseName)
            publishProgress(
                ScanProgress(
                    warehouseName: warehouseName,
                    warehouseID: warehouseID,
                    phase: .identifying,
                    currentFile: "",
                    completed: 0,
                    total: disk.count
                ),
                force: true
            )

            let outcome = await planOffMain(
                existing: existing,
                disk: disk,
                root: root,
                warehouseID: warehouseID,
                warehouseName: warehouseName
            )

            publishProgress(
                ScanProgress(
                    warehouseName: warehouseName,
                    warehouseID: warehouseID,
                    phase: .finishing,
                    currentFile: "",
                    completed: 1,
                    total: 1
                ),
                force: true
            )
            try db.apply(outcome: outcome)
            try await analyzeIfNeeded(db: db, outcome: outcome, root: root, warehouseName: warehouseName, warehouseID: warehouseID)
        } catch {
            statusMessage = error.localizedDescription
        }
        setReconciling(warehouseID, false)
        ThumbnailService.deferGeneration = false
        thumbRefreshToken += 1
        reloadFootage()
        scanProgress = nil
        statusMessage = ""
    }

    private func scanDiskOffMain(root: URL, warehouseID: UUID, warehouseName: String) async -> [DiskEntry] {
        await Task.detached(priority: .userInitiated) {
            ReconcileService.scanDisk(root: root) { path, found in
                Task { @MainActor in
                    self.publishProgress(
                        ScanProgress(
                            warehouseName: warehouseName,
                            warehouseID: warehouseID,
                            phase: .scanning,
                            currentFile: path,
                            completed: found,
                            total: 0
                        )
                    )
                }
            }
        }.value
    }

    private func planOffMain(
        existing: [FootageSnapshot],
        disk: [DiskEntry],
        root: URL,
        warehouseID: UUID,
        warehouseName: String
    ) async -> ReconcileOutcome {
        await Task.detached(priority: .userInitiated) {
            let hasher = FileHasher()
            return ReconcileService.plan(existing: existing, disk: disk, hashOf: { relative in
                let url = root.appendingPathComponent(relative)
                return (try? hasher.hashFile(at: url)) ?? ""
            }, onProgress: { path, done, total in
                Task { @MainActor in
                    self.publishProgress(
                        ScanProgress(
                            warehouseName: warehouseName,
                            warehouseID: warehouseID,
                            phase: .identifying,
                            currentFile: path,
                            completed: done,
                            total: total
                        )
                    )
                }
            })
        }.value
    }

    private func analyzeIfNeeded(
        db: WarehouseDatabase,
        outcome: ReconcileOutcome,
        root: URL,
        warehouseName: String,
        warehouseID: UUID
    ) async throws {
        let thumbs = db.thumbsURL
        let pending = outcome.records.filter { record in
            let thumbExists = FileManager.default.fileExists(
                atPath: thumbs.appendingPathComponent("\(record.id.uuidString).jpg").path
            )
            return ThumbnailService.shouldAnalyze(record, thumbExists: thumbExists)
        }
        for record in pending where record.needsReanalysis {
            try? FileManager.default.removeItem(at: thumbs.appendingPathComponent("\(record.id.uuidString).jpg"))
        }
        try await refreshCaptureMetadata(db: db, outcome: outcome, root: root, warehouseName: warehouseName, warehouseID: warehouseID)
        guard !pending.isEmpty else { return }
        var submitted = 0
        var completed = 0
        try await withThrowingTaskGroup(of: (Int, UUID, String, MediaAnalysis).self) { group in
            func submitMore() {
                while submitted < pending.count, submitted - completed < ThumbnailService.analyzeConcurrency {
                    let index = submitted
                    let record = pending[index]
                    submitted += 1
                    let source = root.appendingPathComponent(record.relativePath)
                    let thumb = thumbs.appendingPathComponent("\(record.id.uuidString).jpg")
                    group.addTask {
                        let analysis = await ThumbnailService.analyze(url: source, thumbnailURL: thumb)
                        return (index, record.id, record.relativePath, analysis)
                    }
                }
            }

            submitMore()
            for try await (index, id, path, analysis) in group {
                try db.updateAnalysis(
                    id: id,
                    phash: analysis.phash,
                    duration: analysis.duration,
                    width: analysis.width,
                    height: analysis.height
                )
                completed += 1
                publishProgress(
                    ScanProgress(
                        warehouseName: warehouseName,
                        warehouseID: warehouseID,
                        phase: .analyzing,
                        currentFile: path,
                        completed: completed,
                        total: pending.count
                    ),
                    force: index == 0 || completed == pending.count
                )
                if completed == pending.count || completed % 128 == 0 {
                    reloadFootage()
                }
                submitMore()
            }
        }
        publishProgress(
            ScanProgress(
                warehouseName: warehouseName,
                warehouseID: warehouseID,
                phase: .analyzing,
                currentFile: pending.last?.relativePath ?? "",
                completed: pending.count,
                total: pending.count
            ),
            force: true
        )
    }

    private func refreshCaptureMetadata(
        db: WarehouseDatabase,
        outcome: ReconcileOutcome,
        root: URL,
        warehouseName: String,
        warehouseID: UUID
    ) async throws {
        let pending = outcome.records.filter { $0.status == .available }
        guard !pending.isEmpty else { return }
        let skipImplausible = preference.ai.skipImplausibleCaptureDates
        var submitted = 0
        var completed = 0
        try await withThrowingTaskGroup(of: (Int, UUID, String, MediaMetadataSnapshot).self) { group in
            func submitMore() {
                while submitted < pending.count, submitted - completed < ThumbnailService.analyzeConcurrency {
                    let index = submitted
                    let record = pending[index]
                    submitted += 1
                    let source = root.appendingPathComponent(record.relativePath)
                    group.addTask {
                        let capture = await MediaMetadata.read(url: source, skipImplausibleHeader: skipImplausible)
                        return (index, record.id, record.relativePath, capture)
                    }
                }
            }

            submitMore()
            for try await (index, id, path, capture) in group {
                try db.updateCaptureMetadata(id: id, capture: capture)
                completed += 1
                publishProgress(
                    ScanProgress(
                        warehouseName: warehouseName,
                        warehouseID: warehouseID,
                        phase: .analyzing,
                        currentFile: path,
                        completed: completed,
                        total: pending.count
                    ),
                    force: index == 0 || completed == pending.count
                )
                if completed == pending.count || completed % 128 == 0 {
                    reloadFootage()
                }
                submitMore()
            }
        }
    }

    private func publishProgress(_ progress: ScanProgress, force: Bool = false) {
        let now = Date().timeIntervalSince1970
        if !force, now - lastProgressPublish < 0.08 { return }
        lastProgressPublish = now
        scanProgress = progress
        statusMessage = ""
    }

    private func reloadFootage() {
        warehouses = preference.warehouses.map { item in
            let online = store.isOnline(item)
            let existing = warehouses.first(where: { $0.id == item.id })
            if online, let db = try? openDatabase(for: item) {
                return WarehouseRuntime(
                    preference: item,
                    isOnline: true,
                    isReconciling: existing?.isReconciling ?? false,
                    footage: (try? db.allFootage()) ?? [],
                    groups: (try? db.duplicateGroups()) ?? []
                )
            }
            return WarehouseRuntime(
                preference: item,
                isOnline: false,
                isReconciling: false,
                footage: existing?.footage ?? [],
                groups: existing?.groups ?? []
            )
        }
        rebuildVisibleResults()
    }

    private func rebuildVisibleResults() {
        let scopes = FootageFilter.resolvedScopes(selection: sidebarSelection, folderScopes: workFolders)
        scopedDuplicateGroups = DuplicateIndex.resolve(warehouses: warehouses, scopes: scopes)
        if case .collection(.duplicates) = sidebarSelection {
            visibleResults = []
            libraryEpoch += 1
            return
        }
        let duplicateIDs = Set(scopedDuplicateGroups.flatMap { $0.members.map(\.id) })
        let items: [(Footage, SearchService.Context)] = warehouses.flatMap { warehouse in
            warehouse.footage.compactMap { footage in
                let context = SearchService.Context(
                    warehouseName: warehouse.preference.name,
                    warehousePath: warehouse.preference.path,
                    isOnline: warehouse.isOnline
                )
                guard FootageFilter.include(
                    footage: footage,
                    isOnline: context.isOnline,
                    selection: sidebarSelection,
                    isDuplicate: duplicateIDs.contains(footage.id),
                    folderScopes: workFolders
                ) else { return nil }
                return (footage, context)
            }
        }
        let ranked = SearchService.rank(query: searchText, items: items, catalog: catalog, locale: localeID)
        visibleResults = SearchService.ordered(ranked, sort: librarySort, ascending: sortAscending)
        libraryEpoch += 1
    }

    private func openDatabase(for item: WarehousePreference) throws -> WarehouseDatabase {
        if let existing = databases[item.id] { return existing }
        let db = try WarehouseDatabase(rootURL: item.url, warehouseID: item.id)
        databases[item.id] = db
        return db
    }

    private func installPlaybackKeys() {
        removePlaybackKeys()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handlePlaybackKey(event)
        }
        fullscreenObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didExitFullScreenNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.playback.noteSystemExitedFullscreen()
            }
        }
    }

    private func removePlaybackKeys() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let fullscreenObserver {
            NotificationCenter.default.removeObserver(fullscreenObserver)
            self.fullscreenObserver = nil
        }
    }

    private func handlePlaybackKey(_ event: NSEvent) -> NSEvent? {
        if Self.isEditingText { return event }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 53 {
            if duplicatesKeyboardActive > 0, !playback.isFullscreen {
                if duplicatePendingDelete != nil {
                    cancelDuplicateTrash()
                    return nil
                }
                return event
            }
            exitFullscreenOrClearSelection()
            return nil
        }
        guard modifiers.isEmpty else { return event }
        if duplicatesKeyboardActive > 0 {
            if duplicatePendingDelete != nil {
                if event.keyCode == 36 || event.keyCode == 76 {
                    confirmDuplicateTrash()
                    return nil
                }
                return event
            }
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "a":
                proposeDuplicateKeepLeft()
                return nil
            case "d":
                proposeDuplicateKeepRight()
                return nil
            case "s":
                keepAllCurrentDuplicate()
                return nil
            default:
                return event
            }
        }
        switch event.charactersIgnoringModifiers {
        case " ":
            guard playback.canPlay else { return event }
            playback.togglePlayPause()
            return nil
        case "p", "P":
            guard playback.media != nil || playback.isFullscreen else { return event }
            playback.toggleFullscreen()
            return nil
        default:
            return event
        }
    }

    static var isEditingText: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        return responder is NSTextView || responder is NSTextField || responder is NSText
    }

    private func database(forFootage id: UUID) -> WarehouseDatabase? {
        guard let footage = warehouses.flatMap(\.footage).first(where: { $0.id == id }) else { return nil }
        return databases[footage.warehouseID]
    }

    private func applyToSelection(_ body: (WarehouseDatabase, [UUID]) throws -> Void) {
        let grouped = Dictionary(grouping: selectedFootage, by: \.warehouseID)
        do {
            for (warehouseID, items) in grouped {
                guard let db = databases[warehouseID] else { continue }
                try body(db, items.map(\.id))
            }
            reloadFootage()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func setReconciling(_ id: UUID, _ value: Bool) {
        if let index = warehouses.firstIndex(where: { $0.id == id }) {
            warehouses[index].isReconciling = value
        }
    }
}

private extension String {
    func removingExtension() -> String {
        (self as NSString).deletingPathExtension
    }
}
