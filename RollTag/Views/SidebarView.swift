import SwiftUI

struct SidebarView: View {
    @Bindable var model: AppModel

    var body: some View {
        List(selection: $model.sidebarSelection) {
            Section(String(localized: "sidebar.library")) {
                ForEach(SmartCollection.allCases) { collection in
                    Label(String(localized: String.LocalizationValue(collection.localizationKey)), systemImage: icon(for: collection))
                        .tag(SidebarSelection.collection(collection))
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
                    .tag(SidebarSelection.warehouse(warehouse.id))
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
