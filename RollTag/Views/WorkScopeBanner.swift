import SwiftUI

struct WorkScopeBanner: View {
    @Bindable var model: AppModel

    var body: some View {
        if !model.workFolders.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
                Text(String(localized: "scope.banner \(model.workFolderSummary)"))
                    .lineLimit(2)
                Spacer(minLength: 8)
                Button(String(localized: "scope.clear")) {
                    model.clearWorkFolders()
                }
                .buttonStyle(.borderless)
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(alignment: .bottom) {
                Divider()
            }
            .help(String(localized: "scope.bannerHelp"))
        }
    }
}
