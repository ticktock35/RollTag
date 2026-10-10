import SwiftUI

struct SidebarView: View {
    @Bindable var model: AppModel

    var body: some View {
        List(selection: $model.sidebarSelection) {
            Section(String(localized: "sidebar.library")) {
                ForEach(SmartCollection.allCases) { collection in
                    collectionRow(collection)
                }
            }

            Section(String(localized: "sidebar.warehouses")) {
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
                                gpxFolderMenu(warehouse: warehouse, folder: node.relativePath)
                            }
                        }
                    }
                    .opacity(warehouse.isOnline ? 1 : 0.7)
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
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            Button {
                model.chooseWarehouseFolder()
            } label: {
                Label(String(localized: "warehouse.add"), systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
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
    private func gpxFolderMenu(warehouse: WarehouseRuntime, folder: String) -> some View {
        if warehouse.isOnline {
            if warehouse.gpx.tracks.isEmpty {
                Button(String(localized: "gpx.import.menu")) {
                    model.chooseGPXFile(for: warehouse.id)
                }
            } else {
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
                Menu(String(localized: "gpx.offset")) {
                    let current = model.folderGPXOffset(warehouseID: warehouse.id, folder: folder)
                    ForEach(GPXOffsetStore.presets, id: \.self) { minutes in
                        Button {
                            model.setFolderGPXOffset(minutes, folder: folder, warehouseID: warehouse.id)
                        } label: {
                            if minutes == current {
                                Label(offsetLabel(minutes), systemImage: "checkmark")
                            } else {
                                Text(offsetLabel(minutes))
                            }
                        }
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

    private func offsetLabel(_ minutes: Int) -> String {
        if minutes == 0 { return "0" }
        return minutes > 0 ? "+\(minutes)" : "\(minutes)"
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
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text(warehouse.isOnline ? String(localized: "warehouse.online") : String(localized: "warehouse.offline"))
                        .font(.caption2)
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
        let key: String
        switch collection {
        case .all: key = "sidebar.count.all"
        case .tagged: key = "sidebar.count.tagged"
        case .untagged: key = "sidebar.count.untagged"
        case .missing: key = "sidebar.count.missing"
        case .duplicates: key = "sidebar.duplicates.pending"
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
        }
    }
}
