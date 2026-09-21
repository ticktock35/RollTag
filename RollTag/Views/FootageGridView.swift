import SwiftUI

struct FootageGridView: View {
    @Bindable var model: AppModel

    private let columns = [GridItem(.adaptive(minimum: 180), spacing: 10)]

    var body: some View {
        ScrollView {
            if model.visibleResults.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, minHeight: 360)
            } else {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(model.visibleResults) { item in
                        FootageCell(
                            item: item,
                            isSelected: model.selectedIDs.contains(item.id),
                            warehouseRoot: model.warehouses.first(where: { $0.id == item.footage.warehouseID && $0.isOnline })?.preference.url,
                            thumbRefreshToken: model.thumbRefreshToken
                        )
                        .onTapGesture {
                            model.selectSingle(item.id, modifiers: NSEvent.modifierFlags)
                        }
                        .contextMenu {
                            Button(String(localized: "finder.reveal")) {
                                model.revealInFinder(item.footage)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "film.stack")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(.secondary)
            Text(emptyTitle)
                .font(.title3.weight(.semibold))
            Text(emptySubtitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    private var emptyTitle: String {
        if model.preference.warehouses.isEmpty {
            return String(localized: "empty.noWarehouses")
        }
        if !model.searchText.isEmpty {
            return String(localized: "empty.noResults")
        }
        return String(localized: "empty.noFootage")
    }

    private var emptySubtitle: String {
        if model.preference.warehouses.isEmpty {
            return String(localized: "empty.noWarehouses.detail")
        }
        if !model.workFolders.isEmpty {
            return String(localized: "empty.noFootage.scoped.detail")
        }
        return String(localized: "empty.noFootage.detail")
    }
}
