import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        ZStack {
            NavigationSplitView {
                SidebarView(model: model)
                    .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
            } detail: {
                rightColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .navigationSplitViewColumnWidth(min: 640, ideal: 960)
            }
            .navigationSplitViewStyle(.prominentDetail)
            .navigationTitle(title)

            FullscreenOverlay(model: model)
        }
        .onDrop(of: [.fileURL], isTargeted: nil, perform: handleDrop)
        .onChange(of: model.showDuplicates) { _, shouldOpen in
            if shouldOpen {
                openWindow(id: "duplicates")
                model.showDuplicates = false
            }
        }
        .onChange(of: model.showShortcuts) { _, shouldOpen in
            if shouldOpen {
                openWindow(id: "shortcuts")
                model.showShortcuts = false
            }
        }
        .onChange(of: model.trimSession) { _, session in
            if session != nil {
                openWindow(id: "trim")
            } else {
                dismissWindow(id: "trim")
            }
        }
        .overlay(alignment: .bottom) {
            ScanStatusOverlay(model: model)
        }
    }

    private var rightColumn: some View {
        VStack(spacing: 0) {
            if model.sidebarSelection == .collection(.duplicates) {
                DuplicatesWorkspace(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VSplitView {
                    HStack(spacing: 0) {
                        PlayerPaneView(model: model)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .frame(minWidth: 280, minHeight: 180)
                        Divider()
                        InspectorView(model: model)
                            .frame(width: 300)
                            .frame(maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, minHeight: 220)

                    VStack(spacing: 0) {
                        libraryBar
                        FootageGridView(model: model)
                            .frame(maxWidth: .infinity, minHeight: 160)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                ScanToolbarItem(model: model)
            }
        }
    }

    private var libraryBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(String(localized: "search.prompt"), text: $model.searchText)
                .textFieldStyle(.plain)
            if !model.searchText.isEmpty {
                Button {
                    model.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Menu {
                ForEach(LibrarySort.allCases) { option in
                    Button {
                        model.selectLibrarySort(option)
                    } label: {
                        if model.librarySort == option {
                            Label(
                                String(localized: String.LocalizationValue(option.localizationKey)),
                                systemImage: "checkmark"
                            )
                        } else {
                            Text(String(localized: String.LocalizationValue(option.localizationKey)))
                        }
                    }
                }
                Divider()
                Button {
                    model.sortAscending = true
                } label: {
                    if model.sortAscending {
                        Label(String(localized: "sort.ascending"), systemImage: "checkmark")
                    } else {
                        Text(String(localized: "sort.ascending"))
                    }
                }
                Button {
                    model.sortAscending = false
                } label: {
                    if !model.sortAscending {
                        Label(String(localized: "sort.descending"), systemImage: "checkmark")
                    } else {
                        Text(String(localized: "sort.descending"))
                    }
                }
            } label: {
                Label(
                    String(localized: String.LocalizationValue(model.librarySort.localizationKey)),
                    systemImage: "arrow.up.arrow.down"
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(String(localized: "sort.title"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(alignment: .top) {
            Divider()
        }
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var title: String {
        switch model.sidebarSelection {
        case .collection(let collection):
            String(localized: String.LocalizationValue(collection.localizationKey))
        case .warehouse(let id):
            model.warehouses.first(where: { $0.id == id })?.preference.name ?? String(localized: "app.name")
        case .tagCategory(let id):
            model.populatedTagCategories.first(where: { $0.id == id })?.title
                ?? model.catalog.categories.first(where: { $0.id == id })?.localizedName(locale: model.localeID)
                ?? String(localized: "tags.customCategory")
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { return }
                Task { @MainActor in
                    model.addWarehouse(url: url)
                }
            }
        }
        return true
    }
}

private struct FullscreenOverlay: View {
    @Bindable var model: AppModel

    var body: some View {
        if model.playback.isFullscreen {
            FullscreenPlayerView(model: model)
                .ignoresSafeArea()
                .zIndex(20)
        }
    }
}

private struct ScanStatusOverlay: View {
    @Bindable var model: AppModel

    var body: some View {
        if model.playback.isFullscreen {
            EmptyView()
        } else if let progress = model.scanProgress {
            ScanProgressBanner(progress: progress)
        } else if !model.statusMessage.isEmpty {
            Text(model.statusMessage)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(12)
        }
    }
}

private struct ScanToolbarItem: View {
    @Bindable var model: AppModel

    var body: some View {
        if let progress = model.scanProgress {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("\(progress.percentInt)%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        } else if model.warehouses.contains(where: \.isReconciling) || model.isBusy {
            ProgressView()
                .controlSize(.small)
        }
    }
}
