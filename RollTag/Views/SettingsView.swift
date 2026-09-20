import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView {
            warehousePane
                .tabItem { Label(String(localized: "settings.warehouses"), systemImage: "externaldrive") }
            aiPane
                .tabItem { Label(String(localized: "settings.ai"), systemImage: "key") }
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 480)
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

    private var aiPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "settings.ai"))
                .font(.title2.weight(.semibold))
            Text(String(localized: "settings.ai.detail"))
                .foregroundStyle(.secondary)
            Text(String(localized: "settings.ai.priority"))
                .font(.callout)
                .foregroundStyle(.secondary)

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
