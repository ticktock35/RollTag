import SwiftUI

struct InspectorView: View {
    @Bindable var model: AppModel

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
                .foregroundStyle(.secondary)
        } else if model.selectedFootage.count == 1, let footage = model.selectedFootage.first {
            VStack(alignment: .leading, spacing: 6) {
                Text(footage.filename)
                    .font(.title3.weight(.semibold))
                if footage.status == .missing {
                    Text(String(localized: "inspector.status.missing"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                LabeledContent(String(localized: "inspector.relativePath")) {
                    Text(footage.relativePath)
                        .textSelection(.enabled)
                }
                LabeledContent(String(localized: "inspector.folder")) {
                    Text(footage.directoryPath.isEmpty ? "—" : footage.directoryPath)
                }
                if let warehouse = model.warehouses.first(where: { $0.id == footage.warehouseID }) {
                    LabeledContent(String(localized: "inspector.warehouse")) {
                        Text(warehouse.preference.name)
                    }
                    LabeledContent(String(localized: "inspector.path")) {
                        Text(warehouse.preference.path)
                            .lineLimit(2)
                    }
                }
                if let duration = footage.duration {
                    LabeledContent(String(localized: "inspector.duration")) {
                        Text(duration, format: .number.precision(.fractionLength(1)))
                    }
                }
                if let timeText = footage.captureMetadata.inspectorTimeText() {
                    LabeledContent(String(localized: "inspector.capturedAt")) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(timeText)
                            if let source = footage.capturedAtSource {
                                Text(captureSourceText(source))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if footage.captureMetadata.hasGPS, let latitude = footage.latitude, let longitude = footage.longitude {
                    LabeledContent(String(localized: "inspector.gps")) {
                        Text(gpsText(latitude: latitude, longitude: longitude, altitude: footage.altitude))
                    }
                }
                if let width = footage.width, let height = footage.height, width > 0, height > 0 {
                    LabeledContent(String(localized: "inspector.dimensions")) {
                        Text("\(width) × \(height)")
                    }
                }
                LabeledContent(String(localized: "inspector.size")) {
                    Text(ByteCountFormatter.string(fromByteCount: footage.size, countStyle: .file))
                }
                if let hash = footage.contentHash, !hash.isEmpty {
                    LabeledContent(String(localized: "inspector.hash")) {
                        Text(hash)
                            .font(.caption.monospaced())
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if footage.status == .missing {
                    missingActions(ids: [footage.id], footage: footage)
                } else {
                    Button(String(localized: "finder.reveal")) {
                        model.revealInFinder(footage)
                    }
                    .buttonStyle(.link)
                }
            }
        } else {
            Text(String(format: String(localized: "inspector.batch"), locale: .current, model.selectedFootage.count))
                .font(.title3.weight(.semibold))
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
                .font(.headline)
            TextEditor(text: Binding(
                get: { footage.userNotes },
                set: { model.updateNotes($0, for: footage.id) }
            ))
            .font(.body)
            .frame(minHeight: 72)
            .scrollContentBackground(.hidden)
            .padding(6)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
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
