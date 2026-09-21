import AppKit
import SwiftUI

struct DuplicatesView: View {
    @Bindable var model: AppModel

    var body: some View {
        DuplicatesWorkspace(model: model)
            .frame(minWidth: 900, minHeight: 600)
    }
}

struct DuplicatesWorkspace: View {
    @Bindable var model: AppModel
    @State private var selectedGroupID: UUID?
    @State private var keeperID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            WorkScopeBanner(model: model)
            VSplitView {
                comparePane
                    .frame(maxWidth: .infinity, minHeight: 240)
                groupList
                    .frame(maxWidth: .infinity, minHeight: 180)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            selectFirstGroupIfNeeded()
            model.duplicateSelectedGroupID = selectedGroupID
            model.duplicatesKeyboardActive += 1
        }
        .onDisappear {
            model.duplicatesKeyboardActive = max(0, model.duplicatesKeyboardActive - 1)
            if model.duplicatesKeyboardActive == 0 {
                model.cancelDuplicateTrash()
            }
        }
        .onChange(of: model.libraryEpoch) {
            reconcileSelection()
        }
        .onChange(of: selectedGroupID) {
            model.duplicateSelectedGroupID = selectedGroupID
        }
        .onChange(of: model.duplicateSelectedGroupID) {
            if let id = model.duplicateSelectedGroupID, id != selectedGroupID {
                selectedGroupID = id
            }
        }
        .onChange(of: model.duplicatePendingDelete?.keeperID) {
            if let id = model.duplicatePendingDelete?.keeperID {
                keeperID = id
            }
        }
        .confirmationDialog(
            String(localized: "duplicates.deleteTitle"),
            isPresented: Binding(
                get: { model.duplicatePendingDelete != nil },
                set: { if !$0 { model.cancelDuplicateTrash() } }
            ),
            titleVisibility: .visible
        ) {
            Button(String(localized: "duplicates.deleteOthers"), role: .destructive) {
                model.confirmDuplicateTrash()
            }
            .keyboardShortcut(.defaultAction)
            Button(String(localized: "duplicates.cancel"), role: .cancel) {
                model.cancelDuplicateTrash()
            }
        } message: {
            if let pending = model.duplicatePendingDelete {
                Text(
                    String(
                        format: String(localized: "duplicates.deleteConfirm"),
                        locale: .current,
                        pending.otherCount,
                        pending.keeperName
                    )
                )
            }
        }
    }

    private var groups: [ResolvedDuplicateGroup] {
        model.scopedDuplicateGroups
    }

    private var selectedGroup: ResolvedDuplicateGroup? {
        if let selectedGroupID,
           let group = groups.first(where: { $0.id == selectedGroupID }) {
            return group
        }
        return groups.first
    }

    private func warehouse(for item: ResolvedDuplicateGroup) -> WarehouseRuntime? {
        model.warehouses.first(where: { $0.id == item.warehouseID })
    }

    private var comparePane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(String(localized: "duplicates.compare"))
                    .font(.headline)
                Spacer()
                Text(String(localized: "duplicates.shortcuts"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            if let item = selectedGroup, let warehouse = warehouse(for: item) {
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(item.members) { member in
                            DuplicateCompareCard(
                                footage: member,
                                warehouse: warehouse,
                                isKeeper: (model.duplicatePendingDelete?.keeperID ?? keeperID ?? item.members.first?.id) == member.id
                            )
                            .onTapGesture {
                                keeperID = member.id
                                model.selectDuplicateMember(member.id)
                            }
                        }
                    }
                    .padding(16)
                }
            } else {
                ContentUnavailableView(
                    String(localized: model.workFolders.isEmpty ? "duplicates.empty" : "duplicates.empty.scoped"),
                    systemImage: "square.on.square",
                    description: Text(String(localized: String.LocalizationValue(model.workFolders.isEmpty ? "duplicates.empty.detail" : "duplicates.empty.scoped.detail")))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }

    private var groupList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(String(localized: "duplicates.groups"))
                    .font(.headline)
                Spacer()
                if !groups.isEmpty {
                    Button(String(localized: "duplicates.batchSeparate")) {
                        keepAllGroups()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Divider()

            if groups.isEmpty {
                ContentUnavailableView(
                    String(localized: model.workFolders.isEmpty ? "duplicates.empty" : "duplicates.empty.scoped"),
                    systemImage: "checkmark.circle",
                    description: Text(String(localized: String.LocalizationValue(model.workFolders.isEmpty ? "duplicates.empty.detail" : "duplicates.empty.scoped.detail")))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(groups) { item in
                            DuplicateGroupCard(
                                warehouseName: model.warehouses.first(where: { $0.id == item.warehouseID })?.preference.name ?? "",
                                members: item.members,
                                isSelected: selectedGroup?.id == item.id
                            ) {
                                selectedGroupID = item.id
                                keeperID = item.members.first?.id
                                if let first = item.members.first {
                                    model.selectDuplicateMember(first.id)
                                }
                            } keepSelected: {
                                keepOne(item)
                            } keepAll: {
                                keepAll(item)
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func keepOne(_ item: ResolvedDuplicateGroup) {
        let keeper = keeperID.flatMap { id in item.members.first(where: { $0.id == id }) } ?? item.members.first
        guard let keeper else { return }
        keeperID = keeper.id
        model.proposeDuplicateKeep(warehouseID: item.warehouseID, group: item.group, keeperID: keeper.id)
    }

    private func keepAll(_ item: ResolvedDuplicateGroup) {
        guard let first = item.members.first else { return }
        model.resolveDuplicates(
            group: item.group,
            warehouseID: item.warehouseID,
            keeperID: first.id,
            unionTags: false,
            keepSeparate: true
        )
    }

    private func keepAllGroups() {
        for item in groups {
            if let first = item.members.first {
                model.resolveDuplicates(
                    group: item.group,
                    warehouseID: item.warehouseID,
                    keeperID: first.id,
                    unionTags: false,
                    keepSeparate: true
                )
            }
        }
    }

    private func selectFirstGroupIfNeeded() {
        guard selectedGroupID == nil, let first = groups.first else { return }
        selectedGroupID = first.id
        keeperID = first.members.first?.id
        if let id = keeperID {
            model.selectDuplicateMember(id)
        }
    }

    private func reconcileSelection() {
        if let selectedGroupID, groups.contains(where: { $0.id == selectedGroupID }) {
            return
        }
        selectedGroupID = groups.first?.id
        keeperID = groups.first?.members.first?.id
    }
}

private struct DuplicateCompareCard: View {
    let footage: Footage
    let warehouse: WarehouseRuntime
    let isKeeper: Bool
    @State private var thumbnail: NSImage?
    @State private var loadingThumb = true
    @State private var missingOriginal = false
    @State private var playing = false
    @State private var playerArmed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            preview
                .frame(width: 280, height: 158)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(footage.filename)
                .font(.headline)
                .lineLimit(2)
            labeled(String(localized: "inspector.folder"), value: footage.directoryPath.isEmpty ? "—" : footage.directoryPath)
            labeled(String(localized: "inspector.warehouse"), value: warehouse.preference.name)
            labeled(String(localized: "inspector.path"), value: warehouse.preference.path)
            if let duration = footage.duration {
                labeled(String(localized: "inspector.duration"), value: duration.formatted(.number.precision(.fractionLength(1))))
            }
            labeled(
                String(localized: "inspector.size"),
                value: ByteCountFormatter.string(fromByteCount: footage.size, countStyle: .file)
            )
            if isKeeper {
                Text(String(localized: "duplicates.willKeep"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(12)
        .frame(width: 304, alignment: .leading)
        .background(
            Color(nsColor: .windowBackgroundColor),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isKeeper ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isKeeper ? 2 : 1)
        }
        .task(id: footage.id) {
            playing = false
            playerArmed = false
            thumbnail = nil
            missingOriginal = false
            loadingThumb = footage.mediaKind != .audio
            guard warehouse.isOnline, footage.mediaKind != .audio else {
                loadingThumb = false
                return
            }
            let url = footage.absoluteURL(warehouseRoot: warehouse.preference.url)
            let thumb = ThumbnailService.thumbnailFileURL(warehouseRoot: warehouse.preference.url, footageID: footage.id)
            if !FileManager.default.fileExists(atPath: url.path) {
                ThumbnailService.removeStoredThumbnail(at: thumb)
                missingOriginal = true
                loadingThumb = false
                return
            }
            if footage.mediaKind == .image {
                thumbnail = await ThumbnailService.ensureImageThumbnail(
                    source: url,
                    thumbnailURL: thumb,
                    maxEdge: ThumbnailService.gridMaxEdge,
                    allowCreate: true
                )
            } else if footage.mediaKind == .video {
                thumbnail = await ThumbnailService.ensureVideoThumbnail(
                    source: url,
                    thumbnailURL: thumb,
                    maxEdge: ThumbnailService.gridMaxEdge,
                    allowCreate: true
                )
            }
            loadingThumb = false
        }
    }

    @ViewBuilder
    private var preview: some View {
        ZStack(alignment: .bottomLeading) {
            Color.black
            if playerArmed, footage.mediaKind.canHoverPlay, warehouse.isOnline {
                IndependentPlayerView(
                    url: footage.absoluteURL(warehouseRoot: warehouse.preference.url),
                    isPlaying: playing,
                    isMuted: footage.mediaKind == .video
                )
            } else if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFit()
            } else if loadingThumb {
                ProgressView()
                    .controlSize(.small)
            } else if footage.mediaKind == .audio {
                Image(systemName: "speaker.wave.2")
                    .foregroundStyle(.white.opacity(0.7))
            } else {
                Image(systemName: missingOriginal ? "eye.slash" : (footage.mediaKind == .image ? "photo" : "film"))
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.7))
            }

            if footage.mediaKind.canHoverPlay, warehouse.isOnline {
                Button {
                    playerArmed = true
                    playing.toggle()
                } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.caption.weight(.semibold))
                        .padding(8)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(8)
            }
        }
    }

    private func labeled(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
                .lineLimit(3)
        }
    }
}

private struct DuplicateGroupCard: View {
    let warehouseName: String
    let members: [Footage]
    let isSelected: Bool
    let onSelect: () -> Void
    let keepSelected: () -> Void
    let keepAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(format: String(localized: "duplicates.group"), locale: .current, members.count))
                        .font(.headline)
                    Text(warehouseName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(folderSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                HStack(spacing: 8) {
                    Button(String(localized: "duplicates.keepThis")) {
                        keepSelected()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(members.isEmpty)
                    Button(String(localized: "duplicates.keepSeparate")) {
                        keepAll()
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isSelected ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture(perform: onSelect)
    }

    private var folderSummary: String {
        let folders = Array(Set(members.map { $0.directoryPath.isEmpty ? "/" : $0.directoryPath })).sorted()
        return folders.joined(separator: "  ·  ")
    }
}
