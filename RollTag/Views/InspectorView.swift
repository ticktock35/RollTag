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
                TagPickerView(model: model, locale: model.localeID)
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
                if let width = footage.width, let height = footage.height, width > 0, height > 0 {
                    LabeledContent(String(localized: "inspector.dimensions")) {
                        Text("\(width) × \(height)")
                    }
                }
                LabeledContent(String(localized: "inspector.size")) {
                    Text(ByteCountFormatter.string(fromByteCount: footage.size, countStyle: .file))
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
                Button(String(localized: "finder.reveal")) {
                    model.revealInFinder(footage)
                }
                .buttonStyle(.link)
            }
        } else {
            Text(String(format: String(localized: "inspector.batch"), locale: .current, model.selectedFootage.count))
                .font(.title3.weight(.semibold))
        }
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
}
