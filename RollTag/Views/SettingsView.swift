import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var glossaryNative = ""
    @State private var glossaryEnglish = ""

    var body: some View {
        TabView {
            warehousePane
                .tabItem { Label(String(localized: "settings.warehouses"), systemImage: "externaldrive") }
            glossaryPane
                .tabItem { Label(String(localized: "settings.glossary"), systemImage: "arrow.left.arrow.right") }
            aiPane
                .tabItem { Label(String(localized: "settings.ai"), systemImage: "key") }
            shortcutsPane
                .tabItem { Label(String(localized: "settings.shortcuts"), systemImage: "keyboard") }
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 620)
        .onAppear {
            DispatchQueue.main.async {
                NSApp.keyWindow?.identifier = NSUserInterfaceItemIdentifier(AppModel.settingsWindowID)
            }
        }
        .onDisappear {
            model.cancelCapturingShortcut()
        }
    }

    private var warehousePane: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "settings.warehouses"))
                .font(.title2.weight(.semibold))
            Text(String(localized: "settings.warehouses.detail"))
                .foregroundStyle(.secondary)

            Table(model.warehouses) {
                TableColumn(String(localized: "settings.name")) { warehouse in
                    TextField("", text: Binding(
                        get: { warehouse.preference.name },
                        set: { model.renameWarehouse(id: warehouse.id, name: $0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
                TableColumn(String(localized: "settings.path")) { warehouse in
                    Text(warehouse.preference.path)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                TableColumn(String(localized: "settings.status")) { warehouse in
                    Text(warehouse.isOnline ? String(localized: "warehouse.online") : String(localized: "warehouse.offline"))
                        .foregroundStyle(warehouse.isOnline ? .primary : .secondary)
                }
                TableColumn(String(localized: "settings.actions")) { warehouse in
                    HStack {
                        Button(String(localized: "warehouse.editPath")) {
                            editPath(warehouse.preference)
                        }
                        Button(String(localized: "warehouse.remove"), role: .destructive) {
                            model.removeWarehouse(id: warehouse.id)
                        }
                    }
                }
            }

            HStack {
                Button(String(localized: "warehouse.add")) {
                    model.chooseWarehouseFolder()
                }
                Spacer()
                Text(String(localized: "settings.removeHint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var glossaryPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "settings.glossary"))
                .font(.title2.weight(.semibold))
            Text(String(localized: "settings.glossary.detail"))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Table(model.preference.glossary.pairs) {
                TableColumn(String(localized: "settings.glossary.native")) { pair in
                    TextField(String(localized: "settings.glossary.nativePlaceholder"), text: Binding(
                        get: { pair.native },
                        set: { model.updateGlossaryPair(id: pair.id, native: $0, english: pair.english) }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
                TableColumn(String(localized: "settings.glossary.english")) { pair in
                    TextField(String(localized: "settings.glossary.englishPlaceholder"), text: Binding(
                        get: { pair.english },
                        set: { model.updateGlossaryPair(id: pair.id, native: pair.native, english: $0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
                TableColumn(String(localized: "settings.actions")) { pair in
                    Button(String(localized: "settings.glossary.delete"), role: .destructive) {
                        model.removeGlossaryPair(id: pair.id)
                    }
                }
            }

            if model.preference.glossary.pairs.isEmpty {
                Text(String(localized: "settings.glossary.empty"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .center, spacing: 8) {
                TextField(String(localized: "settings.glossary.nativePlaceholder"), text: $glossaryNative)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundStyle(.secondary)
                TextField(String(localized: "settings.glossary.englishPlaceholder"), text: $glossaryEnglish)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                    .onSubmit(addGlossaryPair)
                Button(String(localized: "settings.glossary.add")) {
                    addGlossaryPair()
                }
                .disabled(!canAddGlossaryPair)
                Spacer()
            }
        }
    }

    private var canAddGlossaryPair: Bool {
        !glossaryNative.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !glossaryEnglish.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func addGlossaryPair() {
        guard model.addGlossaryPair(native: glossaryNative, english: glossaryEnglish) else { return }
        glossaryNative = ""
        glossaryEnglish = ""
    }

    private var aiPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(String(localized: "settings.ai"))
                    .font(.title2.weight(.semibold))
                Text(String(localized: "settings.ai.detail"))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 16) {
                    Link(String(localized: "settings.ai.keys.gemini"), destination: URL(string: "https://aistudio.google.com/api-keys")!)
                    Link(String(localized: "settings.ai.keys.openai"), destination: URL(string: "https://platform.openai.com/api-keys")!)
                }
                .font(.callout)
                HStack(spacing: 16) {
                    if let url = AIProvider.gemini.usageURL {
                        Link(String(localized: "settings.ai.usage.gemini"), destination: url)
                    }
                    if let url = AIProvider.openai.usageURL {
                        Link(String(localized: "settings.ai.usage.openai"), destination: url)
                    }
                }
                .font(.callout)
                Text(String(localized: "settings.ai.keys.warn"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(String(localized: "settings.ai.priority"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Picker(String(localized: "settings.ai.captureTime"), selection: Binding(
                    get: { model.preference.ai.skipImplausibleCaptureDates },
                    set: { model.updateSkipImplausibleCaptureDates($0) }
                )) {
                    Text(String(localized: "settings.ai.captureTime.skipImplausible")).tag(true)
                    Text(String(localized: "settings.ai.captureTime.preferHeader")).tag(false)
                }
                .pickerStyle(.radioGroup)
                Text(String(localized: "settings.ai.captureTime.detail"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Picker(String(localized: "settings.ai.active"), selection: Binding(
                    get: { model.preference.ai.selectedProvider },
                    set: { model.selectAIProvider($0) }
                )) {
                    Text(String(localized: "settings.ai.none")).tag(Optional<AIProvider>.none)
                    ForEach(AIProvider.allCases) { provider in
                        Text(String(localized: String.LocalizationValue(provider.localizationKey))).tag(Optional(provider))
                    }
                }
                .pickerStyle(.radioGroup)

                Divider()

                ForEach(AIProvider.allCases) { provider in
                    providerRow(provider)
                }

                Text(String(localized: "settings.ai.privacy"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 8)
        }
    }

    private var shortcutsPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "settings.shortcuts"))
                        .font(.title2.weight(.semibold))
                    Text(String(localized: "settings.shortcuts.detail"))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button(String(localized: "settings.shortcuts.resetAll")) {
                    model.resetAllShortcuts()
                }
            }
            Text(String(localized: "settings.shortcuts.menuHint"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !model.shortcutCaptureMessage.isEmpty {
                Text(model.shortcutCaptureMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(ShortcutContext.allCases) { context in
                        shortcutSection(context)
                    }
                }
            }
        }
    }

    private func shortcutSection(_ context: ShortcutContext) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: String.LocalizationValue(context.localizationKey)))
                .font(.headline)
            if context == .library {
                Text(String(localized: "settings.shortcuts.wasd"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if context == .playback {
                Text(String(localized: "settings.shortcuts.fullscreenStep"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 0) {
                ForEach(Array(ShortcutAction.actions(in: context).enumerated()), id: \.element.id) { index, action in
                    if index > 0 {
                        Divider()
                    }
                    shortcutRow(action)
                }
            }
            .padding(.horizontal, 12)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
    }

    private func shortcutRow(_ action: ShortcutAction) -> some View {
        HStack(spacing: 16) {
            Text(String(localized: String.LocalizationValue(action.localizationKey)))
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                if model.capturingShortcut == action {
                    model.cancelCapturingShortcut()
                } else {
                    model.beginCapturingShortcut(action)
                }
            } label: {
                if model.capturingShortcut == action {
                    Text(String(localized: "settings.shortcuts.pressKey"))
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                } else {
                    ShortcutKeyCaps(model.preference.shortcuts.displayLabel(for: action))
                }
            }
            .buttonStyle(.plain)
            .help(String(localized: "settings.shortcuts.recordHelp"))
            Button(String(localized: "settings.shortcuts.resetOne")) {
                model.resetShortcut(action)
            }
            .buttonStyle(.borderless)
            .fixedSize()
        }
        .padding(.vertical, 8)
    }

    private func providerRow(_ provider: AIProvider) -> some View {
        let settings = model.preference.ai.settings(for: provider)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(String(localized: String.LocalizationValue(provider.localizationKey)))
                    .font(.headline)
                Text(String(localized: String.LocalizationValue(provider.capabilityKey)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            SecureField(String(localized: "settings.ai.apiKey"), text: Binding(
                get: { settings.apiKey },
                set: { model.updateAIKey(provider: provider, apiKey: $0, model: settings.model) }
            ))
            if !provider.selectableModels.isEmpty {
                Picker(String(localized: "settings.ai.model"), selection: Binding(
                    get: { model.preference.ai.displayedModel(for: provider) },
                    set: { model.updateAIKey(provider: provider, apiKey: settings.apiKey, model: $0) }
                )) {
                    ForEach(provider.pickerModels(stored: settings.model), id: \.self) { modelID in
                        Text(modelLabel(modelID, provider: provider)).tag(modelID)
                    }
                }
            }
            if !provider.supportsFrameTagging {
                Text(String(localized: "settings.ai.notWired"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func modelLabel(_ modelID: String, provider: AIProvider) -> String {
        if modelID == provider.defaultModel {
            return "\(modelID) · \(String(localized: "settings.ai.modelDefault"))"
        }
        return modelID
    }

    private func editPath(_ warehouse: WarehousePreference) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = warehouse.url
        if panel.runModal() == .OK, let url = panel.url {
            model.updateWarehouse(id: warehouse.id, name: nil, path: url.path)
        }
    }
}
