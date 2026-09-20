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
        VSplitView {
            comparePane
                .frame(maxWidth: .infinity, minHeight: 240)
            groupList
                .frame(maxWidth: .infinity, minHeight: 180)
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

    private var groups: [(WarehouseRuntime, DuplicateGroup)] {
        model.unresolvedDuplicateGroups
    }

    private var selectedPair: (WarehouseRuntime, DuplicateGroup)? {
        if let selectedGroupID,
           let pair = groups.first(where: { $0.1.id == selectedGroupID }) {
            return pair
        }
        return groups.first
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

            if let pair = selectedPair {
                let members = duplicateMembers(warehouse: pair.0, group: pair.1)
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(members) { member in
                            DuplicateCompareCard(
                                footage: member,
                                warehouse: pair.0,
                                isKeeper: (model.duplicatePendingDelete?.keeperID ?? keeperID ?? members.first?.id) == member.id
                            )
                            .onTapGesture {
                                keeperID = member.id
                                model.selectSingle(member.id, modifiers: [])
                            }
                        }
                    }
                    .padding(16)
                }
            } else {
                ContentUnavailableView(
                    String(localized: "duplicates.empty"),
                    systemImage: "square.on.square",
                    description: Text(String(localized: "duplicates.empty.detail"))
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
                    String(localized: "duplicates.empty"),
                    systemImage: "checkmark.circle",
                    description: Text(String(localized: "duplicates.empty.detail"))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(groups, id: \.1.id) { warehouse, group in
                            let members = duplicateMembers(warehouse: warehouse, group: group)
                            DuplicateGroupCard(
                                warehouse: warehouse,
                                group: group,
                                members: members,
                                isSelected: selectedPair?.1.id == group.id
                            ) {
                                selectedGroupID = group.id
                                keeperID = members.first?.id
                                if let first = members.first {
                                    model.selectSingle(first.id, modifiers: [])
                                }
                            } keepSelected: {
                                keepOne(warehouse: warehouse, group: group, members: members)
                            } keepAll: {
                                keepAll(warehouse: warehouse, group: group, members: members)
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func duplicateMembers(warehouse: WarehouseRuntime, group: DuplicateGroup) -> [Footage] {
        warehouse.footage
            .filter { group.memberIDs.contains($0.id) }
            .sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }

    private func keepOne(warehouse: WarehouseRuntime, group: DuplicateGroup, members: [Footage]) {
        let keeper = keeperID.flatMap { id in members.first(where: { $0.id == id }) } ?? members.first
        guard let keeper else { return }
        keeperID = keeper.id
        model.proposeDuplicateKeep(warehouseID: warehouse.id, group: group, keeperID: keeper.id)
    }

    private func keepAll(warehouse: WarehouseRuntime, group: DuplicateGroup, members: [Footage]) {
        guard let first = members.first else { return }
        model.resolveDuplicates(
            group: group,
            warehouseID: warehouse.id,
            keeperID: first.id,
            unionTags: false,
            keepSeparate: true
        )
    }

    private func keepAllGroups() {
        for (runtime, item) in groups {
            if let first = item.memberIDs.first {
                model.resolveDuplicates(
                    group: item,
                    warehouseID: runtime.id,
                    keeperID: first,
                    unionTags: false,
                    keepSeparate: true
                )
            }
        }
    }

    private func selectFirstGroupIfNeeded() {
        guard selectedGroupID == nil, let first = groups.first else { return }
        selectedGroupID = first.1.id
        let members = duplicateMembers(warehouse: first.0, group: first.1)
        keeperID = members.first?.id
        if let id = keeperID {
            model.selectSingle(id, modifiers: [])
        }
    }

    private func reconcileSelection() {
        if let selectedGroupID, groups.contains(where: { $0.1.id == selectedGroupID }) {
            return
        }
        selectedGroupID = groups.first?.1.id
        if let pair = selectedPair {
            let members = duplicateMembers(warehouse: pair.0, group: pair.1)
            keeperID = members.first?.id
        } else {
            keeperID = nil
        }
    }
}

private struct DuplicateCompareCard: View {
    let footage: Footage
    let warehouse: WarehouseRuntime
    let isKeeper: Bool
    @State private var thumbnail: NSImage?
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
            guard warehouse.isOnline else { return }
            let url = footage.absoluteURL(warehouseRoot: warehouse.preference.url)
            let thumb = ThumbnailService.thumbnailFileURL(warehouseRoot: warehouse.preference.url, footageID: footage.id)
            if footage.mediaKind == .image {
                thumbnail = await ThumbnailService.ensureImageThumbnail(
                    source: url,
                    thumbnailURL: thumb,
                    maxEdge: 480,
                    allowCreate: !ThumbnailService.deferGeneration
                )
            } else if footage.mediaKind == .video {
                thumbnail = await ThumbnailService.ensureVideoThumbnail(
                    source: url,
                    thumbnailURL: thumb,
                    maxEdge: 480,
                    allowCreate: !ThumbnailService.deferGeneration
                )
            }
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
            } else if footage.mediaKind == .audio {
                Image(systemName: "speaker.wave.2")
                    .foregroundStyle(.white.opacity(0.7))
            } else {
                ProgressView().controlSize(.small)
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
    let warehouse: WarehouseRuntime
    let group: DuplicateGroup
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
                    Text(warehouse.preference.name)
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
