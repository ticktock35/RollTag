import SwiftUI

struct TagPickerView: View {
    @Bindable var model: AppModel
    @Environment(\.locale) private var swiftLocale
    @State private var customText = ""

    private var locale: String { TagCatalogLoader.localeID(from: swiftLocale) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "tags.title"))
                .font(.headline)

            if model.selectedFootage.isEmpty {
                Text(String(localized: "tags.selectFirst"))
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                currentTags
                customEntry
                if !model.knownCustomTags.isEmpty {
                    customSuggestions
                }
                presetCategories
            }
        }
    }

    private var currentTags: some View {
        FlowWrap(items: TagAssignment.uniqued(model.selectedFootage.flatMap(\.tags))) { tag in
            Button {
                model.removeTags([tag])
            } label: {
                Text(label(for: tag))
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.14), in: Capsule())
            }
            .buttonStyle(.plain)
            .help(String(localized: "tags.remove"))
        }
    }

    private var customEntry: some View {
        HStack(spacing: 8) {
            TextField(String(localized: "tags.customPrompt"), text: $customText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { submitCustom() }
            Button(String(localized: "tags.addCustom")) {
                submitCustom()
            }
            .disabled(customText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var customSuggestions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "tags.customUsed"))
                .font(.caption)
                .foregroundStyle(.secondary)
            FlowWrap(items: model.knownCustomTags) { tag in
                let active = model.selectedFootage.allSatisfy { footage in
                    footage.tags.contains { $0.identityKey == tag.identityKey }
                }
                Button {
                    if active {
                        model.removeTags([tag])
                    } else {
                        model.addTags([tag])
                    }
                } label: {
                    Text(tag.value)
                        .font(.caption)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(active ? Color.accentColor : Color.primary.opacity(0.06), in: Capsule())
                        .foregroundStyle(active ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func submitCustom() {
        if model.addCustomTags(from: customText) {
            customText = ""
        }
    }

    private var presetCategories: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !model.knownCustomTags.isEmpty {
                Divider()
                    .padding(.top, 4)
                    .padding(.bottom, 2)
            }
            Text(String(localized: "tags.presetCategories"))
                .font(.caption)
                .foregroundStyle(.secondary)
            categoryRow
            if let expanded = model.expandedTagCategory,
               let category = model.catalog.categories.first(where: { $0.id == expanded }) {
                detailRow(category)
            }
        }
    }

    private var categoryRow: some View {
        FlowWrap(items: model.catalog.categories) { category in
            Button {
                model.expandedTagCategory = model.expandedTagCategory == category.id ? nil : category.id
            } label: {
                Text(category.localizedName(locale: locale))
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        model.expandedTagCategory == category.id
                            ? Color.accentColor.opacity(0.18)
                            : Color(nsColor: .controlBackgroundColor),
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private func detailRow(_ category: TagCategory) -> some View {
        FlowWrap(items: category.tags) { tag in
            let assignment = TagAssignment.user(category: category.id, value: tag.id)
            let active = model.selectedFootage.allSatisfy { footage in
                footage.tags.contains { $0.identityKey == assignment.identityKey }
            }
            Button {
                if active {
                    model.removeTags([assignment])
                } else {
                    model.addTags([assignment])
                }
            } label: {
                Text(tag.localizedName(locale: locale))
                    .font(.caption)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(active ? Color.accentColor : Color.primary.opacity(0.06), in: Capsule())
                    .foregroundStyle(active ? Color.white : Color.primary)
            }
            .buttonStyle(.plain)
        }
    }

    private func label(for tag: TagAssignment) -> String {
        if tag.isCustom { return tag.value }
        guard let category = model.catalog.categories.first(where: { $0.id == tag.category }) else {
            return tag.value
        }
        let value = category.tags.first(where: { $0.id == tag.value })?.localizedName(locale: locale) ?? tag.value
        return "\(category.localizedName(locale: locale)) · \(value)"
    }
}

struct FlowWrap<Item: Hashable, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        WrappingHStack(spacing: 6) {
            ForEach(items, id: \.self) { item in
                content(item)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct WrappingHStack: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(in: usableWidth(from: proposal), subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(in: bounds.width > 0 ? bounds.width : 280, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: ProposedViewSize(subviews[index].sizeThatFits(.unspecified))
            )
        }
    }

    private func usableWidth(from proposal: ProposedViewSize) -> CGFloat {
        if let width = proposal.width, width.isFinite, width > 0 {
            return width
        }
        return 280
    }

    private func layout(in width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxWidth = max(maxWidth, x - spacing)
        }

        return (CGSize(width: max(maxWidth, width), height: y + rowHeight), origins)
    }
}
