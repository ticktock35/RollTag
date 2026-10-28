import AppKit
import SwiftUI

struct RetouchReviewWorkspace: View {
    @Bindable var model: AppModel
    @State private var selectedID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            WorkScopeBanner(model: model)
            VSplitView {
                comparePane
                    .frame(maxWidth: .infinity, minHeight: 260)
                pairList
                    .frame(maxWidth: .infinity, minHeight: 160)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { selectFirstIfNeeded() }
        .onChange(of: model.libraryEpoch) { reconcileSelection() }
        .onChange(of: selectedID) { _, id in
            if let pair = selectedPair {
                model.selectDuplicateMember(pair.edited.id)
            } else if let id {
                model.selectDuplicateMember(id)
            }
        }
    }

    private var pairs: [RetouchCandidate] {
        model.scopedRetouchPairs
    }

    private var selectedPair: RetouchCandidate? {
        if let selectedID, let pair = pairs.first(where: { $0.id == selectedID }) {
            return pair
        }
        return pairs.first
    }

    private var comparePane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(String(localized: "retouch.compare"))
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Divider()

            if let pair = selectedPair, let warehouse = warehouse(for: pair) {
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(alignment: .top, spacing: 16) {
                        RetouchCompareCard(
                            role: String(localized: "retouch.original"),
                            footage: pair.original,
                            warehouse: warehouse
                        )
                        RetouchCompareCard(
                            role: String(localized: "retouch.edited"),
                            footage: pair.edited,
                            warehouse: warehouse,
                            emphasized: true
                        )
                    }
                    .padding(16)
                }
            } else {
                ContentUnavailableView(
                    String(localized: model.workFolders.isEmpty ? "retouch.empty" : "retouch.empty.scoped"),
                    systemImage: "wand.and.stars",
                    description: Text(
                        String(
                            localized: String.LocalizationValue(
                                model.workFolders.isEmpty ? "retouch.empty.detail" : "retouch.empty.scoped.detail"
                            )
                        )
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }

    private var pairList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(String(localized: "retouch.groups"))
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Divider()

            if pairs.isEmpty {
                ContentUnavailableView(
                    String(localized: model.workFolders.isEmpty ? "retouch.empty" : "retouch.empty.scoped"),
                    systemImage: "checkmark.circle",
                    description: Text(
                        String(
                            localized: String.LocalizationValue(
                                model.workFolders.isEmpty ? "retouch.empty.detail" : "retouch.empty.scoped.detail"
                            )
                        )
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(pairs) { pair in
                            RetouchPairRow(
                                warehouseName: warehouse(for: pair)?.preference.name ?? "",
                                pair: pair,
                                isSelected: selectedPair?.id == pair.id,
                                onSelect: {
                                    selectedID = pair.id
                                },
                                onConfirm: {
                                    selectedID = pair.id
                                    model.confirmRetouch(pair)
                                },
                                onDecline: {
                                    selectedID = pair.id
                                    model.declineRetouch(pair)
                                }
                            )
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func warehouse(for pair: RetouchCandidate) -> WarehouseRuntime? {
        model.warehouses.first(where: { $0.id == pair.warehouseID })
    }

    private func selectFirstIfNeeded() {
        if selectedID == nil {
            selectedID = pairs.first?.id
        }
    }

    private func reconcileSelection() {
        if let selectedID, pairs.contains(where: { $0.id == selectedID }) {
            return
        }
        selectedID = pairs.first?.id
    }
}

private struct RetouchPairRow: View {
    let warehouseName: String
    let pair: RetouchCandidate
    let isSelected: Bool
    let onSelect: () -> Void
    let onConfirm: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(pair.original.filename)  →  \(pair.edited.filename)")
                        .font(.headline)
                        .lineLimit(2)
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
                    Button(String(localized: "retouch.confirm"), action: onConfirm)
                        .buttonStyle(.borderedProminent)
                    Button(String(localized: "retouch.decline"), action: onDecline)
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
        let folders = Array(
            Set(
                [pair.original, pair.edited].map { $0.directoryPath.isEmpty ? "/" : $0.directoryPath }
            )
        ).sorted()
        return folders.joined(separator: "  ·  ")
    }
}

private struct RetouchCompareCard: View {
    let role: String
    let footage: Footage
    let warehouse: WarehouseRuntime
    var emphasized = false
    @State private var thumbnail: NSImage?
    @State private var loadingThumb = true
    @State private var missingOriginal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(role)
                .font(.caption.weight(.semibold))
                .foregroundStyle(emphasized ? Color.accentColor : .secondary)
            preview
                .frame(width: previewSize.width, height: previewSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(footage.filename)
                .font(.headline)
                .lineLimit(2)
            labeled(String(localized: "inspector.folder"), value: footage.directoryPath.isEmpty ? "—" : footage.directoryPath)
            labeled(
                String(localized: "inspector.capturedAt"),
                value: footage.captureMetadata.inspectorTimeText() ?? "—"
            )
            labeled(String(localized: "inspector.gps"), value: gpsText)
            if emphasized {
                Text(String(localized: "retouch.willCopy"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: previewSize.width + 24, alignment: .leading)
        .background(
            Color(nsColor: .windowBackgroundColor),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(emphasized ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: emphasized ? 2 : 1)
        }
        .task(id: footage.id) {
            thumbnail = nil
            missingOriginal = false
            loadingThumb = true
            guard warehouse.isOnline else {
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
            thumbnail = await ThumbnailService.ensureImageThumbnail(
                source: url,
                thumbnailURL: thumb,
                maxEdge: ThumbnailService.storedThumbMaxEdge,
                allowCreate: true
            )
            loadingThumb = false
        }
    }

    private var gpsText: String {
        guard footage.captureMetadata.hasGPS, let latitude = footage.latitude, let longitude = footage.longitude else {
            return "—"
        }
        return String(format: "%.4f°, %.4f°", locale: Locale(identifier: "en_US_POSIX"), latitude, longitude)
    }

    private var previewSize: CGSize {
        let aspect: CGFloat
        if let thumbnail, thumbnail.size.width > 0, thumbnail.size.height > 0 {
            aspect = PreviewLayout.aspect(size: thumbnail.size)
        } else if let width = footage.width, let height = footage.height {
            aspect = PreviewLayout.aspect(width: width, height: height)
        } else {
            aspect = PreviewLayout.videoFallback
        }
        return PreviewLayout.fit(aspect: aspect, maxWidth: 360, maxHeight: 480)
    }

    @ViewBuilder
    private var preview: some View {
        ZStack {
            Color.black
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFit()
            } else if loadingThumb {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: missingOriginal ? "eye.slash" : "photo")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.7))
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
