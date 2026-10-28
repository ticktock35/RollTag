import SwiftUI

struct FolderTimeOffsetSheet: View {
    @Bindable var model: AppModel
    let prompt: FolderTimeOffsetPrompt
    @State private var offset: FolderTimeOffset
    @Environment(\.dismiss) private var dismiss
    @Environment(\.rollTagFonts) private var fonts

    init(model: AppModel, prompt: FolderTimeOffsetPrompt) {
        self.model = model
        self.prompt = prompt
        _offset = State(initialValue: prompt.offset)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "offset.title"))
                    .font(fonts.headline)
                Text(prompt.folderTitle)
                    .font(fonts.callout)
                    .foregroundStyle(.secondary)
                Text(String(localized: "offset.detail"))
                    .font(fonts.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                row(String(localized: "offset.year"), value: $offset.years)
                row(String(localized: "offset.day"), value: $offset.days)
                row(String(localized: "offset.hour"), value: $offset.hours)
                row(String(localized: "offset.minute"), value: $offset.minutes)
                row(String(localized: "offset.second"), value: $offset.seconds)
            }

            HStack {
                Button(String(localized: "offset.reset")) {
                    offset = .zero
                }
                .disabled(offset.isZero)
                Spacer()
                Button(String(localized: "offset.cancel")) {
                    model.folderTimeOffsetPrompt = nil
                    dismiss()
                }
                Button(String(localized: "offset.save")) {
                    model.setFolderTimeOffset(offset, folder: prompt.folder, warehouseID: prompt.warehouseID)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    private func row(_ title: String, value: Binding<Int>) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .frame(width: 52, alignment: .leading)
            Button("-") {
                value.wrappedValue -= 1
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            TextField("", value: value, format: .number)
                .multilineTextAlignment(.center)
                .frame(width: 72)
                .textFieldStyle(.roundedBorder)
            Button("+") {
                value.wrappedValue += 1
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .font(fonts.body)
    }
}
