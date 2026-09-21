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

            if !model.populatedTagCategories.isEmpty {
                Section(String(localized: "sidebar.categories")) {
                    ForEach(model.populatedTagCategories) { category in
                        Label(category.title, systemImage: "folder")
                            .tag(SidebarSelection.tagCategory(category.id))
                    }
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
                        }
                    }
                    .opacity(warehouse.isOnline ? 1 : 0.7)
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

    private func warehouseRow(_ warehouse: WarehouseRuntime) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(warehouse.isOnline ? Color.green.opacity(0.85) : Color.secondary.opacity(0.35))
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(warehouse.preference.name)
                    .foregroundStyle(warehouse.isOnline ? .primary : .secondary)
                if let progress = model.scanProgress, progress.warehouseID == warehouse.id {
                    Text("\(progress.percentInt)% · \(progress.currentFile.isEmpty ? String(localized: "status.scanning") : progress.currentFile)")
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
