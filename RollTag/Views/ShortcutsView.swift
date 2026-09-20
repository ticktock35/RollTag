import SwiftUI

struct ShortcutsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "shortcuts.title"))
                        .font(.title2.weight(.semibold))
                    Text(String(localized: "shortcuts.intro"))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                section(String(localized: "shortcuts.section.general"), items: [
                    .init("warehouse.add", "⌘O"),
                    .init("status.rescan", "⌘R"),
                    .init("duplicates.title", "⌘⇧D"),
                    .init("shortcuts.action.settings", "⌘,"),
                    .init("shortcuts.action.openThis", "⌘/"),
                ])

                section(String(localized: "shortcuts.section.library"), items: [
                    .init("selection.all", "⌘A"),
                    .init("ai.tag.selection", "⌥⌘T"),
                    .init("shortcuts.action.escape", "Esc"),
                ])

                section(String(localized: "shortcuts.section.playback"), items: [
                    .init("player.playPause", String(localized: "shortcuts.key.space")),
                    .init("player.fullscreen", "P"),
                ])

                section(String(localized: "shortcuts.section.duplicates"), items: [
                    .init("shortcuts.action.keepLeft", "A"),
                    .init("shortcuts.action.keepRight", "D"),
                    .init("shortcuts.action.keepAll", "S"),
                    .init("shortcuts.action.confirmTrash", String(localized: "shortcuts.key.return")),
                    .init("shortcuts.action.cancelTrash", "Esc"),
                ])
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 480, minHeight: 420)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func section(_ title: String, items: [ShortcutItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Divider()
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Text(String(localized: String.LocalizationValue(item.actionKey)))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        KeyCaps(item.keys)
                    }
                    .padding(.vertical, 10)
                }
            }
            .padding(.horizontal, 12)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
    }
}

private struct ShortcutItem: Identifiable {
    var id: String { actionKey }
    var actionKey: String
    var keys: String

    init(_ actionKey: String, _ keys: String) {
        self.actionKey = actionKey
        self.keys = keys
    }
}

private struct KeyCaps: View {
    let combo: String

    init(_ combo: String) {
        self.combo = combo
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tokens, id: \.self) { token in
                Text(token)
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Color(nsColor: .windowBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12))
                    }
            }
        }
    }

    private var tokens: [String] {
        var rest = combo
        var parts: [String] = []
        for mark in ["⌘", "⇧", "⌥", "⌃"] where rest.contains(mark) {
            parts.append(mark)
            rest = rest.replacingOccurrences(of: mark, with: "")
        }
        rest = rest.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty {
            parts.append(rest)
        }
        return parts
    }
}
