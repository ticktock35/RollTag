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
    private(set) var sidebarCounts = SmartCollectionCounts()
    var libraryEpoch = 0
    var thumbRefreshToken = 0
    var selectedIDs: Set<UUID> = []
    var libraryGridFocused = false
    var gridColumnCount = 1
    private var selectionAnchorID: UUID?
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
    var pendingMissingDeleteIDs: Set<UUID>?
    var pendingAIConfirmation = false
    private var pendingAINovelTags: [UUID: [TagAssignment]] = [:]
    private var pendingAIBeforeKeys: [UUID: Set<String>] = [:]
    private var pendingAIReplacedTags: [UUID: [TagAssignment]] = [:]
    private var aiStopRequested = false
    var capturingShortcut: ShortcutAction?
    var shortcutCaptureMessage = ""
    let playback = PreviewPlayback()

    let catalog: TagCatalog

    var localeID: String { TagCatalogLoader.localeID() }

    private let store: PreferenceStore
    private let sidecar = SidecarClient()
    private let placeLookup = PlaceNameLookup()
    private let volumeMonitor = VolumeMonitor()
    private var databases: [UUID: WarehouseDatabase] = [:]
    private var lastProgressPublish: TimeInterval = 0
    private var keyMonitor: Any?
    private var fullscreenObserver: NSObjectProtocol?
    private var discardedFootageIDs: Set<UUID> = []
    private var reconcileRunning = false
    private var suppressVolumeReconcileUntil = Date.distantPast
    private var statusHintToken = UUID()
    private var lastInputSourceHintAt = Date.distantPast

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
        selectedIDs.compactMap { footage(id: $0) }
    }

    var focusedFootage: Footage? {
        if let focusedFootageID, selectedIDs.contains(focusedFootageID),
           let item = footage(id: focusedFootageID) {
            return item
        }
        return selectedFootage.first
    }

    var focusedMedia: PreviewMedia? {
        guard let footage = focusedFootage,
              footage.status == .available,
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
        guard selectedFootage.count == 1, let footage = focusedFootage, footage.status == .available,
              footage.mediaKind.canTrim, !footage.isTooSmallToPreview else { return false }
        return warehouses.first(where: { $0.id == footage.warehouseID })?.isOnline == true
    }

    var selectedMissingFootage: [Footage] {
        selectedFootage.filter { $0.status == .missing }
    }

    var visibleMissingIDs: Set<UUID> {
        Set(visibleResults.compactMap { $0.footage.status == .missing ? $0.id : nil })
    }

    func footage(id: UUID) -> Footage? {
        for warehouse in warehouses {
            if let footage = warehouse.footageByID[id] {
                return footage
            }
        }
        return nil
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
                guard let self else { return }
                self.refreshOnlineState()
                if Date() < self.suppressVolumeReconcileUntil { return }
                await self.reconcileOnlineWarehouses()
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

    func beginCapturingShortcut(_ action: ShortcutAction) {
        capturingShortcut = action
        shortcutCaptureMessage = ""
    }

    func cancelCapturingShortcut() {
        capturingShortcut = nil
        shortcutCaptureMessage = ""
    }

    func resetShortcut(_ action: ShortcutAction) {
        preference.shortcuts.set(nil, for: action)
        persistPreference()
        capturingShortcut = nil
        shortcutCaptureMessage = ""
    }

    func resetAllShortcuts() {
        preference.shortcuts = .empty
        persistPreference()
        capturingShortcut = nil
        shortcutCaptureMessage = ""
    }

    @discardableResult
    func addGlossaryPair(native: String, english: String) -> Bool {
        guard let next = preference.glossary.adding(native: native, english: english) else { return false }
        preference.glossary = next
        persistPreference()
        rebuildVisibleResults()
        return true
    }

    func updateGlossaryPair(id: UUID, native: String, english: String) {
        preference.glossary = preference.glossary.updating(id: id, native: native, english: english)
        persistPreference()
        rebuildVisibleResults()
    }

    func removeGlossaryPair(id: UUID) {
        preference.glossary = preference.glossary.removing(id: id)
        persistPreference()
        rebuildVisibleResults()
    }

    @discardableResult
    func applyCapturedShortcut(_ event: NSEvent) -> Bool {
        guard capturingShortcut != nil else { return false }
        if Self.isEditingText {
            cancelCapturingShortcut()
            return false
        }
        if event.keyCode == ShortcutKeys.escape {
            cancelCapturingShortcut()
            return true
        }
        let modifiers = event.modifierFlags.intersection(ShortcutBinding.significantModifiers)
        if modifiers.contains(.command) {
            shortcutCaptureMessage = String(localized: "settings.shortcuts.noCommand")
            return true
        }
        guard let action = capturingShortcut else { return true }
        let binding = ShortcutBinding(keyCode: event.keyCode, modifiers: modifiers)
        if let conflict = preference.shortcuts.conflict(assigning: binding, to: action) {
            let name = String(localized: String.LocalizationValue(conflict.localizationKey))
            shortcutCaptureMessage = String(format: String(localized: "settings.shortcuts.conflict"), locale: .current, name)
            return true
        }
        preference.shortcuts.set(binding, for: action)
        persistPreference()
        capturingShortcut = nil
        shortcutCaptureMessage = ""
        return true
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

    var warehouseCustomTags: [TagAssignment] {
        TagAssignment.uniqued(warehouses.flatMap(\.footage).flatMap(\.tags).filter(\.isCustom))
    }

    var knownCustomTags: [TagAssignment] {
        TagAssignment.recentUsed(warehouseCustomTags, recentValues: preference.recentCustomTags)
    }

    var hasAITaggingRoute: Bool {
        preference.ai.taggingRoute() != nil
    }

    var showsAITagging: Bool {
        hasAITaggingRoute && selectedFootage.contains(where: \.canAITag)
    }

    var canTagWithAI: Bool {
        showsAITagging && canStartSilentAI
    }

    var canStartSilentAI: Bool {
        hasAITaggingRoute && !isBusy && !pendingAIConfirmation
    }

    var showsAIStopButton: Bool {
        isBusy && scanProgress?.phase == .tagging && AITaggingStop.offersStop(total: scanProgress?.total ?? 0)
    }

    var canStopAITagging: Bool {
        showsAIStopButton && !aiStopRequested
    }

    var scopedUntaggedAITaggableIDs: [UUID] {
        FootageFilter.aiTaggableIDs(
            warehouses: warehouses,
            selection: .collection(.untagged),
            folderScopes: workFolders
        )
    }

    var canBatchAITagUntagged: Bool {
        canStartSilentAI && !scopedUntaggedAITaggableIDs.isEmpty
    }

    func showsSilentAITagMenu(for footage: Footage) -> Bool {
        guard hasAITaggingRoute, footage.status != .missing else { return false }
        if selectedIDs.contains(footage.id) {
            return selectedFootage.contains(where: \.canAITag)
        }
        return footage.canAITag
    }

    func addTags(_ tags: [TagAssignment]) {
        let expanded = expandTags(tags, includeEnglishKeywords: localeID != "en")
        applyToSelection { db, ids in
            try db.addTags(expanded, to: ids)
        }
        rememberRecentCustomTags(tags.filter(\.isCustom).map(\.value))
    }

    func tagSelectedWithAI() {
        Task { await tagWithAI(ids: selectedFootage.map(\.id), requireConfirmation: true) }
    }

    func tagUntaggedWithAI() {
        Task { await tagWithAI(ids: scopedUntaggedAITaggableIDs, requireConfirmation: false) }
    }

    func tagGridSelectionWithAI(clicked id: UUID) {
        let ids = FootageFilter.silentAITargetIDs(clicked: id, selectedIDs: selectedIDs)
        Task { await tagWithAI(ids: ids, requireConfirmation: false) }
    }

    func tagWithAI(ids: [UUID], requireConfirmation: Bool = true) async {
        guard !ids.isEmpty, !isBusy, !pendingAIConfirmation else { return }
        let routes = preference.ai.taggingRoutes()
        guard !routes.isEmpty else {
            showTemporaryStatus(String(localized: "ai.missingKey"))
            return
        }

        if !sidecar.isRunning {
            sidecar.start()
        }

        isBusy = true
        aiStopRequested = false
        defer {
            isBusy = false
            aiStopRequested = false
            if scanProgress?.phase == .tagging {
                scanProgress = nil
            }
        }

        let customValues = Set(warehouseCustomTags.map(\.value))
        let blockedCustomKeys = AITagSuggester.blockedCustomKeys(
            customValues: warehouseCustomTags.map(\.value),
            glossary: preference.glossary
        )
        let catalogPayload = AITagSuggester.catalogPayload(
            catalog: catalog,
            locale: localeID,
            customValues: []
        )
        let items = warehouses.flatMap(\.footage).filter { ids.contains($0.id) }
        var tagged = 0
        var failed = 0
        var skipped = 0
        var lastError = ""
        var stopped = false
        var lastResult = ""
        pendingAINovelTags = [:]
        pendingAIBeforeKeys = [:]
        pendingAIReplacedTags = [:]

        for (index, footage) in items.enumerated() {
            if shouldStopAITagging {
                stopped = true
                break
            }
            publishAIProgress(
                footage: footage,
                index: index,
                total: items.count,
                provider: routes.first?.provider,
                lastResult: lastResult
            )

            guard footage.canAITag else {
                skipped += 1
                lastResult = AITaggingProgressCopy.skipped(footage.filename)
                continue
            }

            guard let warehouse = warehouses.first(where: { $0.id == footage.warehouseID }),
                  warehouse.isOnline
            else {
                failed += 1
                lastResult = AITaggingProgressCopy.failed(footage.filename, provider: nil)
                continue
            }

            let url = footage.absoluteURL(warehouseRoot: warehouse.preference.url)
            let live = await MediaMetadata.read(
                url: url,
                skipImplausibleHeader: preference.ai.skipImplausibleCaptureDates
            )
            if shouldStopAITagging {
                stopped = true
                break
            }
            let place = await resolvedPlace(stored: footage.captureMetadata, live: live)
            if shouldStopAITagging {
                stopped = true
                break
            }
            let gpsTags = expandTags(
                PathTagMatcher.geocodeAssignments(place, catalog: catalog),
                includeEnglishKeywords: true
            )
            let frames = await FrameExtractor.jpegStills(url: url)
            if shouldStopAITagging {
                stopped = true
                break
            }
            if frames.isEmpty {
                if !gpsTags.isEmpty, let db = databases[footage.warehouseID] {
                    try? db.addTags(gpsTags, to: [footage.id])
                    tagged += 1
                    lastResult = AITaggingProgressCopy.succeeded(footage.filename, provider: nil)
                } else {
                    skipped += 1
                    lastError = String(localized: "ai.noFrames")
                    lastResult = AITaggingProgressCopy.skipped(footage.filename)
                }
                continue
            }

            do {
                let vision = await VisionFrameAnalyzer.observe(frames: frames)
                let context = AITagSuggester.contextPayload(
                    footage: footage,
                    warehouseName: warehouse.preference.name,
                    live: live,
                    place: place,
                    vision: vision
                )
                let (payload, provider) = try await suggestWithFallback(
                    routes: routes,
                    frames: frames,
                    catalog: catalogPayload,
                    context: context,
                    examples: AITaggingExample.strippingBlockedCustoms(
                        preference.ai.examples,
                        blockedCustomKeys: blockedCustomKeys
                    ),
                    onRoute: { provider in
                        self.publishAIProgress(
                            footage: footage,
                            index: index,
                            total: items.count,
                            provider: provider,
                            lastResult: lastResult
                        )
                    }
                )
                let warehouseCustoms = warehouse.footage.flatMap(\.tags).filter(\.isCustom).map(\.value)
                let userCustomKeys = Set(
                    warehouse.footage.flatMap(\.tags)
                        .filter { $0.isCustom && $0.source == "user" }
                        .map { KeywordGlossary.lookupKey($0.value) }
                        .filter { !$0.isEmpty }
                )
                let pathTags = PathTagMatcher.assignments(
                    relativePath: footage.relativePath,
                    catalog: catalog,
                    customValues: PathTagMatcher.inheritableCustoms(
                        warehouseCustoms,
                        relativePath: footage.relativePath,
                        userCustomKeys: userCustomKeys
                    ),
                    blockedCustomKeys: blockedCustomKeys
                )
                let staleFolderTags = PathTagMatcher.staleFolderNameTags(
                    footage.tags,
                    relativePath: footage.relativePath,
                    userCustomKeys: userCustomKeys
                )
                let aiTags = AITagSuggester.assignments(
                    from: payload,
                    catalog: catalog,
                    customValues: customValues,
                    blockedCustomKeys: blockedCustomKeys,
                    vision: vision
                )
                let incoming = TagAssignment.uniqued(pathTags + aiTags)
                let expanded = TagAssignment.uniqued(
                    gpsTags + AITagSuggester.finalize(
                        expandTags(incoming, includeEnglishKeywords: true),
                        blockedCustomKeys: blockedCustomKeys,
                        vision: vision
                    )
                )
                let existingByKey = Dictionary(
                    footage.tags.map { ($0.identityKey, $0) },
                    uniquingKeysWith: { TagAssignment.sourceRank($0.source) <= TagAssignment.sourceRank($1.source) ? $0 : $1 }
                )
                let written = expanded.filter { tag in
                    guard let current = existingByKey[tag.identityKey] else { return true }
                    return TagAssignment.sourceRank(tag.source) <= TagAssignment.sourceRank(current.source)
                }
                if let db = databases[footage.warehouseID] {
                    if pendingAIReplacedTags[footage.id] == nil {
                        pendingAIReplacedTags[footage.id] = footage.tags.filter { $0.source == "ai" }
                    }
                    if pendingAIBeforeKeys[footage.id] == nil {
                        pendingAIBeforeKeys[footage.id] = Set(footage.tags.map(\.identityKey))
                    }
                    try db.removeTags(source: "ai", from: [footage.id])
                    if !staleFolderTags.isEmpty {
                        try db.removeTags(staleFolderTags, from: [footage.id])
                    }
                    if !written.isEmpty {
                        try db.addTags(written, to: [footage.id])
                        let gpsKeys = Set(gpsTags.map(\.identityKey))
                        pendingAINovelTags[footage.id, default: []].append(
                            contentsOf: written.filter { !gpsKeys.contains($0.identityKey) }
                        )
                    }
                }
                tagged += 1
                lastResult = AITaggingProgressCopy.succeeded(footage.filename, provider: provider)
            } catch {
                if AITaggingStop.isCancellation(error) || shouldStopAITagging {
                    stopped = true
                    break
                }
                if !gpsTags.isEmpty, let db = databases[footage.warehouseID] {
                    try? db.addTags(gpsTags, to: [footage.id])
                }
                failed += 1
                lastError = error.localizedDescription
                lastResult = AITaggingProgressCopy.failed(
                    footage.filename,
                    provider: routes.last?.provider
                )
            }
        }

        reloadFootage()
        let remaining = max(0, items.count - tagged - skipped - failed)
        var toast = aiStatusMessage(
            total: items.count,
            tagged: tagged,
            skipped: skipped,
            failed: failed,
            remaining: remaining,
            stopped: stopped,
            lastError: lastError
        )
        if !lastResult.isEmpty, !toast.contains(lastResult) {
            toast += "\n" + lastResult
        }
        showTemporaryStatus(toast)
        if tagged > 0, requireConfirmation, !stopped, !pendingAINovelTags.isEmpty {
            pendingAIConfirmation = true
        } else {
            pendingAINovelTags = [:]
            pendingAIBeforeKeys = [:]
            pendingAIReplacedTags = [:]
        }
    }

    func stopAITagging() {
        guard showsAIStopButton else { return }
        aiStopRequested = true
        sidecar.cancelInFlightSuggest()
    }

    private var shouldStopAITagging: Bool {
        aiStopRequested || Task.isCancelled
    }

    func confirmAITagging() {
        recordAITaggingExamples()
        pendingAIConfirmation = false
        pendingAINovelTags = [:]
        pendingAIBeforeKeys = [:]
        pendingAIReplacedTags = [:]
        statusMessage = ""
    }

    func cancelAITagging() {
        guard pendingAIConfirmation else { return }
        let replaced = pendingAIReplacedTags
        let novel = pendingAINovelTags
        let before = pendingAIBeforeKeys
        pendingAIConfirmation = false
        pendingAINovelTags = [:]
        pendingAIBeforeKeys = [:]
        pendingAIReplacedTags = [:]
        for (id, previous) in replaced {
            guard let db = database(forFootage: id) else { continue }
            try? db.removeTags(source: "ai", from: [id])
            if !previous.isEmpty {
                try? db.addTags(previous, to: [id])
            }
            let newPath = (novel[id] ?? []).filter { tag in
                tag.source == "path" && !(before[id] ?? []).contains(tag.identityKey)
            }
            if !newPath.isEmpty {
                try? db.removeTags(newPath, from: [id])
            }
        }
        reloadFootage()
        showTemporaryStatus(String(localized: "ai.cancelled"))
        if playback.isFullscreen {
            playback.exitFullscreen()
        }
    }

    private func aiStatusMessage(
        total: Int,
        tagged: Int,
        skipped: Int,
        failed: Int,
        remaining: Int,
        stopped: Bool,
        lastError: String
    ) -> String {
        if stopped {
            if skipped == 0, failed == 0 {
                return String(format: String(localized: "ai.stopped"), locale: .current, tagged, remaining)
            }
            return String(
                format: String(localized: "ai.stoppedDetail"),
                locale: .current,
                tagged,
                skipped,
                failed,
                remaining
            )
        }
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

    private func recordAITaggingExamples() {
        var fresh: [AITaggingExample] = []
        for (id, proposed) in pendingAINovelTags {
            guard let footage = footage(id: id) else { continue }
            let before = pendingAIBeforeKeys[id] ?? []
            let kept = footage.tags.filter { !before.contains($0.identityKey) }
            if let example = AITaggingExample.make(ai: proposed, kept: kept) {
                fresh.append(example)
            }
        }
        guard !fresh.isEmpty else { return }
        preference.ai.examples = AITaggingExample.recording(preference.ai.examples, inserting: fresh)
        persistPreference()
    }

    private func resolvedPlace(stored: MediaMetadataSnapshot, live: MediaMetadataSnapshot) async -> String? {
        let latitude = stored.latitude ?? live.latitude
        let longitude = stored.longitude ?? live.longitude
        guard let latitude, let longitude else { return nil }
        return await placeLookup.placeName(latitude: latitude, longitude: longitude)
    }

    private func publishAIProgress(
        footage: Footage,
        index: Int,
        total: Int,
        provider: AIProvider?,
        lastResult: String
    ) {
        let warehouseName = warehouses.first(where: { $0.id == footage.warehouseID })?.preference.name
            ?? String(localized: "ai.tag")
        publishProgress(
            ScanProgress(
                warehouseName: warehouseName,
                warehouseID: footage.warehouseID,
                phase: .tagging,
                currentFile: footage.filename,
                completed: index,
                total: total,
                currentProvider: provider.map(AITaggingProgressCopy.providerTitle) ?? "",
                currentProviderID: provider?.rawValue ?? "",
                lastFileResult: lastResult
            ),
            force: true
        )
    }

    private func suggestWithFallback(
        routes: [AITaggingRoute],
        frames: [Data],
        catalog: [String: Any],
        context: [String: Any],
        examples: [AITaggingExample],
        onRoute: ((AIProvider) -> Void)? = nil
    ) async throws -> ([String: Any], AIProvider) {
        var lastError: Error = SidecarError.unavailable
        for route in routes {
            onRoute?(route.provider)
            do {
                let payload = try await sidecar.suggestTags(
                    provider: route.provider,
                    apiKey: route.apiKey,
                    model: route.model,
                    frames: frames,
                    catalog: catalog,
                    context: context,
                    examples: examples
                )
                return (payload, route.provider)
            } catch {
                if AITaggingStop.isCancellation(error) {
                    throw error
                }
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
        let expanded = expandTags(tags, includeEnglishKeywords: true)
        applyToSelection { db, ids in
            try db.removeTags(expanded, from: ids)
        }
    }

    private func expandTags(_ tags: [TagAssignment], includeEnglishKeywords: Bool) -> [TagAssignment] {
        StockKeywordExpander.expand(
            tags,
            catalog: catalog,
            includeEnglishKeywords: includeEnglishKeywords,
            glossary: preference.glossary
        )
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
                patchWarehouse(warehouseID, groupID: group.id, resolution: .keepSeparate)
            } else {
                try db.mergeMetadata(keeperID: keeperID, from: others, unionTags: unionTags)
                if deleteOthers {
                    suppressVolumeReconcileUntil = Date().addingTimeInterval(5)
                    discardedFootageIDs.formUnion(others.map(\.id))
                    var failed: [String] = []
                    var removed = Set<UUID>()
                    for other in others {
                        let url = other.absoluteURL(warehouseRoot: warehouse.preference.url)
                        do {
                            if FileManager.default.fileExists(atPath: url.path) {
                                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                            }
                            try db.removeFootage(id: other.id)
                            removed.insert(other.id)
                        } catch {
                            failed.append(other.filename)
                            discardedFootageIDs.remove(other.id)
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
                    patchWarehouse(
                        warehouseID,
                        removing: removed,
                        groupID: group.id,
                        dropGroup: true
                    )
                } else {
                    try db.setResolution(groupID: group.id, resolution: .merged)
                    patchWarehouse(warehouseID, groupID: group.id, resolution: .merged)
                }
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func keepAllDuplicateGroups(_ items: [ResolvedDuplicateGroup]) {
        let grouped = Dictionary(grouping: items, by: \.warehouseID)
        for (warehouseID, list) in grouped {
            guard let db = databases[warehouseID] else { continue }
            for item in list {
                try? db.setResolution(groupID: item.group.id, resolution: .keepSeparate)
            }
            patchWarehouse(warehouseID, groupIDs: Set(list.map(\.id)), resolution: .keepSeparate)
        }
    }

    private func patchWarehouse(
        _ warehouseID: UUID,
        removing removedIDs: Set<UUID> = [],
        groupID: UUID? = nil,
        groupIDs: Set<UUID> = [],
        resolution: DuplicateResolution? = nil,
        dropGroup: Bool = false
    ) {
        guard let index = warehouses.firstIndex(where: { $0.id == warehouseID }) else { return }
        let current = warehouses[index]
        var footage = current.footage
        var groups = current.groups
        if !removedIDs.isEmpty {
            footage.removeAll { removedIDs.contains($0.id) }
        }
        if dropGroup, let groupID {
            groups.removeAll { $0.id == groupID }
        } else if let resolution {
            let ids = groupID.map { Set([$0]) } ?? groupIDs
            for i in groups.indices where ids.contains(groups[i].id) {
                groups[i].resolution = resolution
            }
        }
        warehouses[index] = WarehouseRuntime(
            preference: current.preference,
            isOnline: current.isOnline,
            isReconciling: current.isReconciling,
            footage: footage,
            groups: groups
        )
        rebuildVisibleResults()
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
            selectionAnchorID = focusedFootageID
        } else if modifiers.contains(.shift) {
            let ids = visibleResults.map(\.id)
            let last = selectionAnchorID ?? focusedFootageID ?? selectedIDs.first
            guard let last, let from = ids.firstIndex(of: last), let to = ids.firstIndex(of: id) else {
                selectedIDs = [id]
                focusedFootageID = id
                selectionAnchorID = id
                presentFocusedMedia()
                return
            }
            let range = from <= to ? ids[from...to] : ids[to...from]
            selectedIDs = Set(range)
            focusedFootageID = id
        } else {
            selectedIDs = [id]
            focusedFootageID = id
            selectionAnchorID = id
        }
        presentFocusedMedia()
    }

    func updateGridColumnCount(width: CGFloat) {
        let columns = GridNavigation.columnCount(width: width)
        if gridColumnCount != columns {
            gridColumnCount = columns
        }
    }

    func moveLibrarySelection(_ direction: GridNavigation.Direction, extend: Bool) {
        let ids = visibleResults.map(\.id)
        guard !ids.isEmpty else { return }
        let current = focusedFootageID.flatMap { ids.firstIndex(of: $0) }
            ?? ids.firstIndex(where: { selectedIDs.contains($0) })
        let nextIndex: Int
        if let current {
            guard let moved = GridNavigation.index(
                moving: direction,
                from: current,
                count: ids.count,
                columns: gridColumnCount
            ) else { return }
            nextIndex = moved
        } else {
            nextIndex = (direction == .left || direction == .up) ? ids.count - 1 : 0
        }
        selectSingle(ids[nextIndex], modifiers: extend ? .shift : [])
    }

    func stepFullscreenMedia(_ delta: Int) {
        guard playback.isFullscreen else { return }
        let ids = fullscreenPlaylistIDs()
        guard !ids.isEmpty else { return }
        let current = focusedFootageID.flatMap { ids.firstIndex(of: $0) }
            ?? ids.firstIndex(where: { selectedIDs.contains($0) })
        let start = current ?? (delta > 0 ? -1 : ids.count)
        guard let nextIndex = GridNavigation.firstPresentableIndex(
            moving: delta,
            from: start,
            count: ids.count,
            isPresentable: { canPresentInPlayer(ids[$0]) }
        ) else { return }
        selectSingle(ids[nextIndex], modifiers: [])
        playback.play()
    }

    private func fullscreenPlaylistIDs() -> [UUID] {
        if duplicatesKeyboardActive > 0, let pair = currentDuplicatePair() {
            return duplicateMembers(pair).map(\.id)
        }
        return visibleResults.map(\.id)
    }

    private func canPresentInPlayer(_ id: UUID) -> Bool {
        guard let footage = warehouses.flatMap(\.footage).first(where: { $0.id == id }) else { return false }
        guard footage.status == .available else { return false }
        guard let warehouse = warehouses.first(where: { $0.id == footage.warehouseID }), warehouse.isOnline else {
            return false
        }
        return true
    }

    func selectAllVisible() {
        selectedIDs = Set(visibleResults.map(\.id))
        if let focusedFootageID, selectedIDs.contains(focusedFootageID) {
            presentFocusedMedia()
            return
        }
        focusedFootageID = visibleResults.first?.id
        selectionAnchorID = focusedFootageID
        presentFocusedMedia()
    }

    func clearSelection() {
        selectedIDs = []
        focusedFootageID = nil
        selectionAnchorID = nil
        playback.present(nil)
    }

    func exitFullscreenOrClearSelection() {
        if playback.isFullscreen {
            playback.exitFullscreen()
        } else {
            clearSelection()
        }
    }

    func toggleSelectedFullscreen() {
        if playback.isFullscreen {
            playback.toggleFullscreen()
            return
        }
        if focusedFootageID == nil, duplicatesKeyboardActive > 0,
           let pair = currentDuplicatePair() {
            let keeper = duplicateMembers(pair).first
            focusedFootageID = keeper?.id
            if let id = keeper?.id {
                selectedIDs = [id]
            }
        }
        presentFocusedMedia()
        guard playback.media != nil else { return }
        playback.toggleFullscreen()
    }

    private func hintSwitchInputSourceIfNeeded(_ event: NSEvent) {
        guard ShortcutKeys.shouldHintSwitchInputSource(
            characters: event.characters,
            keyCode: event.keyCode,
            boundLetterKeyCodes: preference.shortcuts.letterKeyCodes
        ) else { return }
        let now = Date()
        guard now.timeIntervalSince(lastInputSourceHintAt) > 8 else { return }
        lastInputSourceHintAt = now
        showTemporaryStatus(String(localized: "status.switchInputSource"))
    }

    private func showTemporaryStatus(_ message: String, seconds: Double = 10) {
        statusMessage = message
        let token = UUID()
        statusHintToken = token
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            if statusHintToken == token, statusMessage == message {
                statusMessage = ""
            }
        }
    }

    func revealInFinder(_ footage: Footage) {
        guard footage.status == .available else {
            openContainingFolder(footage)
            return
        }
        guard let warehouse = warehouses.first(where: { $0.id == footage.warehouseID }), warehouse.isOnline else { return }
        NSWorkspace.shared.activateFileViewerSelecting([footage.absoluteURL(warehouseRoot: warehouse.preference.url)])
    }

    func openContainingFolder(_ footage: Footage) {
        guard let warehouse = warehouses.first(where: { $0.id == footage.warehouseID }) else { return }
        let fileURL = footage.absoluteURL(warehouseRoot: warehouse.preference.url)
        let folder = fileURL.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: folder.path) {
            NSWorkspace.shared.open(folder)
            return
        }
        if warehouse.isOnline, FileManager.default.fileExists(atPath: warehouse.preference.url.path) {
            NSWorkspace.shared.open(warehouse.preference.url)
            return
        }
        statusMessage = String(localized: "finder.folderMissing")
    }

    func proposeDeleteMissing(_ ids: Set<UUID>) {
        let missing = Set(ids.compactMap { footage(id: $0) }.filter { $0.status == .missing }.map(\.id))
        guard !missing.isEmpty else { return }
        pendingMissingDeleteIDs = missing
    }

    func proposeDeleteAllVisibleMissing() {
        proposeDeleteMissing(visibleMissingIDs)
    }

    func cancelMissingDelete() {
        pendingMissingDeleteIDs = nil
    }

    func confirmDeleteMissing() {
        guard let ids = pendingMissingDeleteIDs else { return }
        pendingMissingDeleteIDs = nil
        removeMissingRecords(ids)
    }

    private func removeMissingRecords(_ ids: Set<UUID>) {
        let items = ids.compactMap { footage(id: $0) }.filter { $0.status == .missing }
        guard !items.isEmpty else { return }
        discardedFootageIDs.formUnion(items.map(\.id))
        let grouped = Dictionary(grouping: items, by: \.warehouseID)
        var removed = Set<UUID>()
        var failed = 0
        for (warehouseID, list) in grouped {
            guard let db = databases[warehouseID] else {
                failed += list.count
                discardedFootageIDs.subtract(list.map(\.id))
                continue
            }
            var gone = Set<UUID>()
            for item in list {
                do {
                    try db.removeFootage(id: item.id)
                    gone.insert(item.id)
                } catch {
                    discardedFootageIDs.remove(item.id)
                    failed += 1
                }
            }
            if !gone.isEmpty {
                patchWarehouse(warehouseID, removing: gone)
                removed.formUnion(gone)
            }
        }
        selectedIDs.subtract(removed)
        if let focusedFootageID, removed.contains(focusedFootageID) {
            self.focusedFootageID = selectedIDs.first
            presentFocusedMedia()
        }
        if failed > 0 {
            statusMessage = String(format: String(localized: "missing.deleteFailed"), locale: .current, failed)
        }
    }

    private func rememberRecentCustomTags(_ values: [String]) {
        let next = TagAssignment.rememberRecent(preference.recentCustomTags, used: values)
        guard next != preference.recentCustomTags else { return }
        preference.recentCustomTags = next
        persistPreference()
    }

    func persistPreference() {
        do {
            try store.save(preference)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func reconcileOnlineWarehouses() async {
        if reconcileRunning { return }
        reconcileRunning = true
        defer { reconcileRunning = false }
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
            let applied = outcome.omitting(ids: discardedFootageIDs)
            try db.apply(outcome: applied)
            try await analyzeIfNeeded(db: db, outcome: applied, root: root, warehouseName: warehouseName, warehouseID: warehouseID)
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
        let pending = outcome.records.filter {
            $0.status == .available && $0.capturedAt == nil && ($0.capturedAtLocal == nil || $0.capturedAtLocal?.isEmpty == true)
        }
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
        sidebarCounts = FootageFilter.collectionCounts(
            warehouses: warehouses,
            scopes: scopes,
            duplicateGroups: scopedDuplicateGroups.count
        )
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
        let ranked = SearchService.rank(
            query: searchText,
            items: items,
            catalog: catalog,
            locale: localeID,
            glossary: preference.glossary
        )
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
        if applyCapturedShortcut(event) { return nil }
        if Self.isSettingsKeyWindow { return event }
        if Self.isEditingText { return event }
        let shortcuts = preference.shortcuts
        if handleLibraryArrowKey(event) {
            return nil
        }
        if playback.isFullscreen, duplicatePendingDelete == nil, let delta = shortcuts.fullscreenStepDelta(
            keyCode: event.keyCode,
            modifiers: event.modifierFlags
        ) {
            hintSwitchInputSourceIfNeeded(event)
            stepFullscreenMedia(delta)
            return nil
        }
        if shortcuts.matches(event, .clearSelection) || shortcuts.matches(event, .duplicateCancelTrash) {
            if playback.isFullscreen {
                playback.exitFullscreen()
                return nil
            }
            if duplicatesKeyboardActive > 0 {
                if duplicatePendingDelete != nil {
                    cancelDuplicateTrash()
                    return nil
                }
                if shortcuts.matches(event, .duplicateCancelTrash) {
                    return event
                }
            }
            if pendingAIConfirmation {
                cancelAITagging()
                return nil
            }
            if shortcuts.matches(event, .clearSelection) {
                exitFullscreenOrClearSelection()
                return nil
            }
        }
        if pendingAIConfirmation, shortcuts.matches(event, .confirmAI) {
            if duplicatesKeyboardActive > 0, duplicatePendingDelete != nil,
               shortcuts.matches(event, .duplicateConfirmTrash) {
                confirmDuplicateTrash()
                return nil
            }
            confirmAITagging()
            return nil
        }
        if duplicatesKeyboardActive > 0 {
            if duplicatePendingDelete != nil {
                if shortcuts.matches(event, .duplicateConfirmTrash) {
                    confirmDuplicateTrash()
                    return nil
                }
                return event
            }
            if shortcuts.matches(event, .duplicateKeepLeft) {
                hintSwitchInputSourceIfNeeded(event)
                proposeDuplicateKeepLeft()
                return nil
            }
            if shortcuts.matches(event, .duplicateKeepRight) {
                hintSwitchInputSourceIfNeeded(event)
                proposeDuplicateKeepRight()
                return nil
            }
            if shortcuts.matches(event, .duplicateKeepAll) {
                hintSwitchInputSourceIfNeeded(event)
                keepAllCurrentDuplicate()
                return nil
            }
            if shortcuts.matches(event, .fullscreen) {
                hintSwitchInputSourceIfNeeded(event)
                toggleSelectedFullscreen()
                return nil
            }
            if shortcuts.matches(event, .playPause) {
                hintSwitchInputSourceIfNeeded(event)
                if playback.media == nil { presentFocusedMedia() }
                guard playback.canPlay else { return event }
                playback.togglePlayPause()
                return nil
            }
            if ShortcutKeys.looksLikeIMECharacter(event.characters) {
                hintSwitchInputSourceIfNeeded(event)
                return nil
            }
            return event
        }
        if shortcuts.matches(event, .playPause) {
            hintSwitchInputSourceIfNeeded(event)
            guard playback.canPlay else { return event }
            playback.togglePlayPause()
            return nil
        }
        if shortcuts.matches(event, .fullscreen) {
            hintSwitchInputSourceIfNeeded(event)
            toggleSelectedFullscreen()
            return nil
        }
        if ShortcutKeys.looksLikeIMECharacter(event.characters) {
            hintSwitchInputSourceIfNeeded(event)
        }
        return event
    }

    private func handleLibraryArrowKey(_ event: NSEvent) -> Bool {
        guard libraryGridFocused else { return false }
        guard duplicatesKeyboardActive == 0 else { return false }
        guard !playback.isFullscreen else { return false }
        guard sidebarSelection != .collection(.duplicates) else { return false }
        guard Self.isLibraryKeyWindow else { return false }
        guard !Self.isFocusInSidebar() else { return false }
        guard let direction = preference.shortcuts.libraryGridDirection(
            keyCode: event.keyCode,
            modifiers: event.modifierFlags
        ) else { return false }
        if ShortcutKeys.isUSLetter(event.keyCode) {
            hintSwitchInputSourceIfNeeded(event)
        }
        moveLibrarySelection(direction, extend: event.modifierFlags.contains(.shift))
        return true
    }

    static var isEditingText: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        return responder is NSTextView || responder is NSTextField || responder is NSText
    }

    static let settingsWindowID = "settings"

    static var isSettingsKeyWindow: Bool {
        NSApp.keyWindow?.identifier?.rawValue == settingsWindowID
    }

    static var isLibraryKeyWindow: Bool {
        guard let window = NSApp.keyWindow else { return false }
        let id = window.identifier?.rawValue ?? ""
        return id != "duplicates" && id != "shortcuts" && id != "trim" && id != settingsWindowID
    }

    static func isFocusInSidebar(_ window: NSWindow? = NSApp.keyWindow) -> Bool {
        var responder = window?.firstResponder
        while let current = responder {
            if current is NSTableView || current is NSOutlineView {
                return true
            }
            responder = current.nextResponder
        }
        return false
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

enum AITaggingProgressCopy {
    static func providerTitle(_ provider: AIProvider) -> String {
        String(localized: String.LocalizationValue(provider.localizationKey))
    }

    static func succeeded(_ filename: String, provider: AIProvider?) -> String {
        if let provider {
            return String(
                format: String(localized: "ai.last.success"),
                locale: .current,
                filename,
                providerTitle(provider)
            )
        }
        return String(format: String(localized: "ai.last.successUnknown"), locale: .current, filename)
    }

    static func failed(_ filename: String, provider: AIProvider?) -> String {
        if let provider {
            return String(
                format: String(localized: "ai.last.failed"),
                locale: .current,
                filename,
                providerTitle(provider)
            )
        }
        return String(format: String(localized: "ai.last.failedUnknown"), locale: .current, filename)
    }

    static func skipped(_ filename: String) -> String {
        String(format: String(localized: "ai.last.skipped"), locale: .current, filename)
    }

    static func attributedLine(_ string: String) -> AttributedString {
        var text = AttributedString(string)
        for provider in AIProvider.taggingPriority {
            guard let url = provider.usageURL else { continue }
            let name = providerTitle(provider)
            var searchStart = text.startIndex
            while searchStart < text.endIndex, let range = text[searchStart...].range(of: name) {
                text[range].link = url
                text[range].underlineStyle = .single
                searchStart = range.upperBound
            }
        }
        return text
    }
}

enum AITaggingStop {
    static func offersStop(total: Int) -> Bool {
        total > 10
    }

    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}

private extension String {
    func removingExtension() -> String {
        (self as NSString).deletingPathExtension
    }
}
