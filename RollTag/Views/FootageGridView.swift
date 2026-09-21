import AppKit
import SwiftUI

struct FootageGridView: View {
    @Bindable var model: AppModel
    @FocusState private var gridFocused: Bool

    private let columns = [
        GridItem(.adaptive(minimum: GridNavigation.cellMinimum), spacing: GridNavigation.spacing)
    ]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if model.visibleResults.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity, minHeight: 360)
                } else {
                    LazyVGrid(columns: columns, spacing: GridNavigation.rowSpacing) {
                        ForEach(model.visibleResults) { item in
                            FootageCell(
                                item: item,
                                isSelected: model.selectedIDs.contains(item.id),
                                warehouseRoot: model.warehouses.first(where: { $0.id == item.footage.warehouseID && $0.isOnline })?.preference.url,
                                thumbRefreshToken: model.thumbRefreshToken
                            )
                            .id(item.id)
                            .onTapGesture {
                                focusGrid()
                                model.selectSingle(item.id, modifiers: NSEvent.modifierFlags)
                            }
                            .contextMenu {
                                if item.footage.status == .missing {
                                    Button(String(localized: "finder.openFolder")) {
                                        model.openContainingFolder(item.footage)
                                    }
                                    Button(String(localized: "missing.delete"), role: .destructive) {
                                        model.proposeDeleteMissing([item.id])
                                    }
                                } else {
                                    Button(String(localized: "finder.reveal")) {
                                        model.revealInFinder(item.footage)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, GridNavigation.horizontalPadding)
                    .padding(.vertical, 10)
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture().onEnded { focusGrid() }
            )
            .focusable()
            .focused($gridFocused)
            .focusEffectDisabled()
            .onChange(of: gridFocused) { _, focused in
                model.libraryGridFocused = focused
            }
            .onChange(of: model.focusedFootageID) { _, id in
                guard let id, model.libraryGridFocused || gridFocused else { return }
                proxy.scrollTo(id, anchor: .center)
            }
        }
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { model.updateGridColumnCount(width: geo.size.width) }
                    .onChange(of: geo.size.width) { _, width in
                        model.updateGridColumnCount(width: width)
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func focusGrid() {
        gridFocused = true
        model.libraryGridFocused = true
        if let window = NSApp.keyWindow, AppModel.isFocusInSidebar(window) {
            window.makeFirstResponder(nil)
        }
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
        if model.sidebarSelection == .collection(.missing) {
            return String(localized: "empty.noMissing")
        }
        return String(localized: "empty.noFootage")
    }

    private var emptySubtitle: String {
        if model.preference.warehouses.isEmpty {
            return String(localized: "empty.noWarehouses.detail")
        }
        if model.sidebarSelection == .collection(.missing) {
            return String(localized: "empty.noMissing.detail")
        }
        if !model.workFolders.isEmpty {
            return String(localized: "empty.noFootage.scoped.detail")
        }
        return String(localized: "empty.noFootage.detail")
    }
}
