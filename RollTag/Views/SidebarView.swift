import SwiftUI

struct SidebarView: View {
    @Bindable var model: AppModel
    @Environment(\.rollTagFonts) private var fonts

    var body: some View {
        List(selection: $model.sidebarSelection) {
            Section(String(localized: "sidebar.library")) {
                ForEach(SmartCollection.allCases) { collection in
                    collectionRow(collection)
                }
            }

            Section {
                ForEach(model.warehouses) { warehouse in
                    OutlineGroup(
                        [
                            WarehouseFolderNode(
                                warehouseID: warehouse.id,
                                relativePath: "",
                                name: warehouse.preference.name,
                                children: warehouse.folderNodes.isEmpty ? nil : warehouse.folderNodes
                            )
                        ],
                        children: \.children
                    ) { node in
                        if node.isWarehouseRoot {
                            warehouseRow(warehouse)
                                .tag(SidebarSelection.warehouse(warehouse.id))
                                .contextMenu {
                                    itineraryFolderMenu(warehouse: warehouse, folder: "")
                                    gpxFolderMenu(warehouse: warehouse, folder: "")
                                }
                        } else {
                            let ref = FolderRef(warehouseID: warehouse.id, relativePath: node.relativePath)
                            HStack(spacing: 6) {
                                Button {
                                    model.toggleWorkFolder(ref)
                                } label: {
                                    Image(systemName: model.isWorkFolder(ref) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(model.isWorkFolder(ref) ? Color.accentColor : Color.secondary)
                                        .imageScale(.small)
                                }
                                .buttonStyle(.borderless)
                                .help(String(localized: model.isWorkFolder(ref) ? "scope.unpinHelp" : "scope.pinHelp"))
                                Label(node.name, systemImage: "folder")
                                    .foregroundStyle(warehouse.isOnline ? .primary : .secondary)
                            }
                            .tag(SidebarSelection.warehouseFolder(warehouse.id, node.relativePath))
                            .help(node.relativePath)
                            .contextMenu {
                                itineraryFolderMenu(warehouse: warehouse, folder: node.relativePath)
                                gpxFolderMenu(warehouse: warehouse, folder: node.relativePath)
                            }
                        }
                    }
                    .opacity(warehouse.isOnline ? 1 : 0.7)
                }
            } header: {
                HStack {
                    Text(String(localized: "sidebar.warehouses"))
                    Spacer()
                    Button {
                        model.chooseWarehouseFolder()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "warehouse.add"))
                }
            }

            if model.hasItineraries {
                Section(String(localized: "sidebar.itineraries")) {
                    ForEach(model.warehouses.filter { !$0.itineraries.isEmpty }) { warehouse in
                        ForEach(warehouse.itineraries) { itinerary in
                            Button {
                                model.openItinerary(warehouseID: warehouse.id, itineraryID: itinerary.id)
                            } label: {
                                Label(
                                    model.itineraryRowTitle(warehouse: warehouse, itinerary: itinerary),
                                    systemImage: "map"
                                )
                            }
                            .buttonStyle(.plain)
                            .tag(SidebarSelection.itinerary(warehouse.id, itinerary.id))
                            .badge(itinerary.memberIDs.count)
                            .help(warehouse.preference.name)
                            .id("itinerary-\(itinerary.id.uuidString)")
                            .contextMenu {
                                Button(String(localized: "itinerary.rename")) {
                                    model.beginRenameItinerary(warehouseID: warehouse.id, itineraryID: itinerary.id)
                                }
                                Button(String(localized: "itinerary.delete"), role: .destructive) {
                                    model.deleteItinerary(warehouseID: warehouse.id, itineraryID: itinerary.id)
                                }
                            }
                        }
                    }
                }
            }

            if !model.populatedTagCategories.isEmpty {
                Section(String(localized: "sidebar.categories")) {
                    ForEach(model.populatedTagCategories) { category in
                        Label(category.title, systemImage: "folder")
                            .tag(SidebarSelection.tagCategory(category.id))
                    }
                }
            }

            if model.hasImportedGPX {
                Section(String(localized: "sidebar.gpx")) {
                    ForEach(model.warehouses.filter { !$0.gpx.tracks.isEmpty }) { warehouse in
                        ForEach(warehouse.gpx.tracks) { track in
                            Label(gpxRowTitle(warehouse: warehouse, track: track), systemImage: "point.topleft.down.to.point.bottomright.curved")
                                .tag(SidebarSelection.gpx(warehouse.id, track.filename))
                                .badge(model.gpxMatchCount(warehouse: warehouse, filename: track.filename))
                                .help(warehouse.preference.name)
                        }
                    }
                }
            }
        }
        .font(fonts.body)
        .listStyle(.sidebar)
        .onChange(of: model.sidebarSelection) { _, _ in
            if AppModel.isFocusInSidebar() {
                model.libraryGridFocused = false
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                Button {
                    model.chooseWarehouseFolder()
                } label: {
                    Label(String(localized: "warehouse.add"), systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    @ViewBuilder
    private func collectionRow(_ collection: SmartCollection) -> some View {
        let row = Label(String(localized: String.LocalizationValue(collection.localizationKey)), systemImage: icon(for: collection))
            .badge(badge(for: collection))
            .tag(SidebarSelection.collection(collection))
            .help(help(for: collection))
        if collection == .untagged {
            row.contextMenu {
                Button(String(localized: "ai.tag.batch")) {
                    model.tagUntaggedWithAI()
                }
                .disabled(!model.canBatchAITagUntagged)
                .help(String(localized: "ai.tag.batch.untagged.help"))
            }
        } else {
            row
        }
    }

    @ViewBuilder
    private func itineraryFolderMenu(warehouse: WarehouseRuntime, folder: String) -> some View {
        if warehouse.isOnline {
            Button(String(localized: "itinerary.importGPX")) {
                model.chooseGPXFile(for: warehouse.id, folder: folder, createItinerary: true)
            }
            Button(String(localized: "itinerary.createTimeline")) {
                model.createTimelineItinerary(warehouseID: warehouse.id, folder: folder)
            }
            Button(String(localized: "offset.edit")) {
                model.beginFolderTimeOffset(warehouseID: warehouse.id, folder: folder)
            }
            if !warehouse.gpx.tracks.isEmpty {
                Divider()
            }
        }
    }

    @ViewBuilder
    private func gpxFolderMenu(warehouse: WarehouseRuntime, folder: String) -> some View {
        if warehouse.isOnline, !warehouse.gpx.tracks.isEmpty {
            Menu(String(localized: "gpx.apply")) {
                ForEach(warehouse.gpx.tracks) { track in
                    Button {
                        model.applyGPX(track.filename, toFolder: folder, warehouseID: warehouse.id)
                    } label: {
                        if model.effectiveGPXFilename(warehouseID: warehouse.id, folder: folder) == track.filename {
                            Label(track.displayName, systemImage: "checkmark")
                        } else {
                            Text(track.displayName)
                        }
                    }
                }
                if model.hasDirectGPXAssignment(warehouseID: warehouse.id, folder: folder) {
                    Divider()
                    Button(String(localized: "gpx.clear")) {
                        model.clearGPXAssignment(folder: folder, warehouseID: warehouse.id)
                    }
                }
            }
        }
    }

    private func gpxRowTitle(warehouse: WarehouseRuntime, track: ImportedGPXTrack) -> String {
        let named = model.warehouses.filter { !$0.gpx.tracks.isEmpty }
        if named.count > 1 {
            return "\(warehouse.preference.name) / \(track.displayName)"
        }
        return track.displayName
    }

    private func warehouseRow(_ warehouse: WarehouseRuntime) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(warehouse.isOnline ? Color.green.opacity(0.85) : Color.secondary.opacity(0.35))
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(warehouse.preference.name)
                    .foregroundStyle(warehouse.isOnline ? .primary : .secondary)
                if let progress = model.scanProgress, progress.warehouseID == warehouse.id {
                    Text("\(progress.showsPercent ? "\(progress.percentInt)% · " : "")\(progress.currentFile.isEmpty ? String(localized: "status.scanning") : progress.currentFile)")
                        .font(fonts.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text(warehouse.isOnline ? String(localized: "warehouse.online") : String(localized: "warehouse.offline"))
                        .font(fonts.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func badge(for collection: SmartCollection) -> Int {
        model.sidebarCounts.value(for: collection)
    }

    private func help(for collection: SmartCollection) -> String {
        let count = model.sidebarCounts.value(for: collection)
        if collection == .duplicates {
            if count == 0 {
                return String(localized: "sidebar.duplicates.none")
            }
            return String(format: String(localized: "sidebar.duplicates.pending"), locale: .current, count)
        }
        if collection == .retouch {
            if count == 0 {
                return String(localized: "sidebar.retouch.none")
            }
            return String(format: String(localized: "sidebar.retouch.pending"), locale: .current, count)
        }
        let key: String
        switch collection {
        case .all: key = "sidebar.count.all"
        case .tagged: key = "sidebar.count.tagged"
        case .untagged: key = "sidebar.count.untagged"
        case .missing: key = "sidebar.count.missing"
        case .duplicates: key = "sidebar.duplicates.pending"
        case .retouch: key = "sidebar.retouch.pending"
        }
        return String(format: String(localized: String.LocalizationValue(key)), locale: .current, count)
    }

    private func icon(for collection: SmartCollection) -> String {
        switch collection {
        case .all: return "square.grid.2x2"
        case .tagged: return "tag.fill"
        case .untagged: return "tag"
        case .missing: return "eye.slash"
        case .duplicates: return "square.on.square"
        case .retouch: return "wand.and.stars"
        }
    }
}
