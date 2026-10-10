import SwiftUI

struct HelpView: View {
    @Bindable var model: AppModel
    @State private var selectedID: String?

    private var topics: [HelpTopic] {
        UserGuide.topics(localeID: model.localeID)
    }

    private var selected: HelpTopic? {
        topics.first(where: { $0.id == selectedID }) ?? topics.first
    }

    var body: some View {
        NavigationSplitView {
            List(topics, selection: $selectedID) { topic in
                Text(topic.title)
                    .tag(topic.id)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 260)
        } detail: {
            if let selected {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(selected.title)
                            .font(.title2.weight(.semibold))
                        HelpBodyView(blocks: selected.blocks)
                            .frame(maxWidth: 560, alignment: .leading)
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(nsColor: .windowBackgroundColor))
            } else {
                ContentUnavailableView(
                    String(localized: "help.title"),
                    systemImage: "book",
                    description: Text(String(localized: "help.missing"))
                )
            }
        }
        .navigationTitle(String(localized: "help.title"))
        .frame(minWidth: 640, minHeight: 480)
        .onAppear {
            if selectedID == nil {
                selectedID = topics.first?.id
            }
        }
    }
}

private struct HelpBodyView: View {
    var blocks: [HelpBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let text):
                    Text(UserGuide.inlineMarkdown(text))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                case .bullets(let items):
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("•")
                                    .foregroundStyle(.secondary)
                                Text(UserGuide.inlineMarkdown(item))
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.leading, 8)
                case .steps(let items):
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("\(index + 1).")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                    .frame(minWidth: 22, alignment: .trailing)
                                Text(UserGuide.inlineMarkdown(item))
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.leading, 4)
                }
            }
        }
    }
}
