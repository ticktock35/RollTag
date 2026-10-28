import SwiftUI

struct InspectorView: View {
    @Bindable var model: AppModel
    @Environment(\.rollTagFonts) private var fonts

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if model.canBeginTrim {
                    Button(String(localized: "trim.open")) {
                        model.beginTrim()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isBusy)
                }
                if model.showsAITagging {
                    Button(String(localized: "ai.tag")) {
                        model.tagSelectedWithAI()
                    }
                    .disabled(!model.canTagWithAI)
                    .help(String(localized: "ai.tag.help"))
                }
                if model.showsAIStopButton {
                    Button(String(localized: "ai.stop")) {
                        model.stopAITagging()
                    }
                    .disabled(!model.canStopAITagging)
                    .help(String(localized: "ai.stop.help"))
                }
                if model.pendingAIConfirmation {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "ai.confirm.detail"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            Button(String(localized: "ai.confirm")) {
                                model.confirmAITagging()
                            }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                            Button(String(localized: "ai.cancel"), role: .cancel) {
                                model.cancelAITagging()
                            }
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                TagPickerView(model: model)
                if model.selectedFootage.count == 1, let footage = model.selectedFootage.first {
                    notes(footage)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var header: some View {
        if model.selectedFootage.isEmpty {
            Text(String(localized: "inspector.empty"))
                .font(fonts.body)
                .foregroundStyle(.secondary)
        } else if model.selectedFootage.count == 1, let footage = model.selectedFootage.first {
            VStack(alignment: .leading, spacing: 6) {
                Text(footage.filename)
                    .font(fonts.title3)
                if footage.status == .missing {
                    Text(String(localized: "inspector.status.missing"))
                        .font(fonts.caption2)
                        .foregroundStyle(.orange)
                }
                inspectorRow(String(localized: "inspector.relativePath")) {
                    Text(footage.relativePath)
                        .textSelection(.enabled)
                }
                inspectorRow(String(localized: "inspector.folder")) {
                    Text(footage.directoryPath.isEmpty ? "—" : footage.directoryPath)
                }
                if let warehouse = model.warehouses.first(where: { $0.id == footage.warehouseID }) {
                    inspectorRow(String(localized: "inspector.warehouse")) {
                        Text(warehouse.preference.name)
                    }
                    inspectorRow(String(localized: "inspector.path")) {
                        Text(warehouse.preference.path)
                            .lineLimit(2)
                    }
                }
                if let duration = footage.duration {
                    inspectorRow(String(localized: "inspector.duration")) {
                        Text(duration, format: .number.precision(.fractionLength(1)))
                    }
                }
                if let timeText = footage.captureMetadata.inspectorTimeText() {
                    inspectorRow(String(localized: "inspector.capturedAt")) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(timeText)
                            if let source = footage.capturedAtSource {
                                Text(captureSourceText(source))
                                    .font(fonts.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if footage.captureMetadata.hasGPS, let latitude = footage.latitude, let longitude = footage.longitude {
                    inspectorRow(String(localized: "inspector.gps")) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(gpsText(latitude: latitude, longitude: longitude, altitude: footage.altitude))
                            if footage.captureMetadata.resolvedGPSSource == .gpx {
                                Text(String(localized: "inspector.gpsSource.gpx"))
                                    .font(fonts.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if let width = footage.width, let height = footage.height, width > 0, height > 0 {
                    inspectorRow(String(localized: "inspector.dimensions")) {
                        Text("\(width) × \(height)")
                    }
                }
                inspectorRow(String(localized: "inspector.size")) {
                    Text(ByteCountFormatter.string(fromByteCount: footage.size, countStyle: .file))
                }
                if let hash = footage.contentHash, !hash.isEmpty {
                    inspectorRow(String(localized: "inspector.hash")) {
                        Text(hash)
                            .font(fonts.caption.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(2)
                    }
                }
                if footage.isTooSmallToPreview {
                    Text(
                        String(
                            format: String(localized: "preview.unavailable.incomplete"),
                            locale: .current,
                            ByteCountFormatter.string(fromByteCount: footage.size, countStyle: .file)
                        )
                    )
                    .font(fonts.caption)
                    .foregroundStyle(.secondary)
                }
                if footage.status == .missing {
                    missingActions(ids: [footage.id], footage: footage)
                } else {
                    Button(String(localized: "finder.reveal")) {
                        model.revealInFinder(footage)
                    }
                    .buttonStyle(.link)
                    if model.shouldOfferOpenWith(for: footage) {
                        Menu(String(localized: "openWith.button")) {
                            OpenWithMenuContent(footage: footage, model: model)
                        }
                        .help(String(localized: "openWith.help"))
                    }
                }
            }
            .font(fonts.body)
        } else {
            Text(String(format: String(localized: "inspector.batch"), locale: .current, model.selectedFootage.count))
                .font(fonts.title3)
            if !model.selectedMissingFootage.isEmpty {
                missingActions(ids: Set(model.selectedMissingFootage.map(\.id)), footage: model.selectedMissingFootage.count == 1 ? model.selectedMissingFootage.first : nil)
            }
        }
    }

    @ViewBuilder
    private func missingActions(ids: Set<UUID>, footage: Footage?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let footage {
                Button(String(localized: "finder.openFolder")) {
                    model.openContainingFolder(footage)
                }
                .buttonStyle(.bordered)
            }
            Button(String(localized: ids.count > 1 ? "missing.deleteSelected" : "missing.delete"), role: .destructive) {
                model.proposeDeleteMissing(ids)
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 4)
    }

    private func notes(_ footage: Footage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "inspector.notes"))
                .font(fonts.headline)
            TextEditor(text: Binding(
                get: { footage.userNotes },
                set: { model.updateNotes($0, for: footage.id) }
            ))
            .font(fonts.body)
            .frame(minHeight: 72)
            .scrollContentBackground(.hidden)
            .padding(6)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    private func inspectorRow<Content: View>(_ title: String, @ViewBuilder value: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .foregroundStyle(.secondary)
                .fixedSize()
            value()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(fonts.body)
    }

    private func captureSourceText(_ source: CaptureTimeSource) -> String {
        switch source {
        case .header:
            String(localized: "inspector.capturedAtSource.header")
        case .djiFilename:
            String(localized: "inspector.capturedAtSource.djiFilename")
        case .fileDate:
            String(localized: "inspector.capturedAtSource.fileDate")
        }
    }

    private func gpsText(latitude: Double, longitude: Double, altitude: Double?) -> String {
        var text = String(format: "%.4f°, %.4f°", locale: Locale(identifier: "en_US_POSIX"), latitude, longitude)
        if let altitude {
            text += String(format: " · %.0f m", locale: Locale(identifier: "en_US_POSIX"), altitude)
        }
        return text
    }
}
