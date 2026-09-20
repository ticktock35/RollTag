import Foundation

struct PreferenceFile: Codable, Equatable {
    var version: Int
    var warehouses: [WarehousePreference]
    var ai: AIPreference

    static let currentVersion = 1

    enum CodingKeys: String, CodingKey {
        case version
        case warehouses
        case ai
    }

    static var empty: PreferenceFile {
        PreferenceFile(version: currentVersion, warehouses: [], ai: .empty)
    }

    init(version: Int, warehouses: [WarehousePreference], ai: AIPreference = .empty) {
        self.version = version
        self.warehouses = warehouses
        self.ai = ai
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? PreferenceFile.currentVersion
        warehouses = try container.decodeIfPresent([WarehousePreference].self, forKey: .warehouses) ?? []
        ai = try container.decodeIfPresent(AIPreference.self, forKey: .ai) ?? .empty
    }
}

enum AIProvider: String, CaseIterable, Identifiable, Codable, Hashable {
    case gemini
    case openai
    case twelvelabs
    case dashscope
    case anthropic

    var id: String { rawValue }

    var localizationKey: String { "ai.provider.\(rawValue)" }
    var capabilityKey: String { "ai.capability.\(rawValue)" }

    static let taggingPriority: [AIProvider] = [.gemini, .openai]

    var supportsFrameTagging: Bool { Self.taggingPriority.contains(self) }

    var selectableModels: [String] {
        switch self {
        case .gemini:
            ["gemini-3.5-flash-lite", "gemini-3.1-flash-lite", "gemini-3.5-flash", "gemini-3.8-flash"]
        case .openai:
            ["gpt-4.1-mini", "gpt-4.1", "gpt-4o"]
        case .twelvelabs:
            ["pegasus-1.2"]
        case .dashscope:
            ["qwen-vl-max", "qwen-vl-plus"]
        case .anthropic:
            ["claude-sonnet-4-5", "claude-sonnet-4", "claude-opus-4"]
        }
    }

    var defaultModel: String { selectableModels.first ?? "" }

    var retiredModelReplacements: [String: String] {
        switch self {
        case .gemini:
            [
                "gemini-2.5-flash-lite": "gemini-3.5-flash-lite",
                "gemini-2.0-flash-lite": "gemini-3.5-flash-lite",
                "gemini-2.0-flash": "gemini-3.5-flash",
                "gemini-2.5-flash": "gemini-3.5-flash",
                "gemini-2.5-pro": "gemini-3.8-flash",
            ]
        default:
            [:]
        }
    }

    func canonicalModel(_ stored: String) -> String {
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.isEmpty ? defaultModel : trimmed
        return retiredModelReplacements[candidate] ?? candidate
    }

    func pickerModels(stored: String) -> [String] {
        let resolved = canonicalModel(stored)
        guard !selectableModels.contains(resolved) else {
            return selectableModels
        }
        return selectableModels + [resolved]
    }
}

struct AITaggingRoute: Equatable {
    var provider: AIProvider
    var apiKey: String
    var model: String
}

struct AIProviderSettings: Codable, Equatable {
    var apiKey: String
    var model: String
}

struct AIPreference: Codable, Equatable {
    var selectedProvider: AIProvider?
    var providers: [AIProvider: AIProviderSettings]

    static var empty: AIPreference {
        AIPreference(selectedProvider: nil, providers: [:])
    }

    func settings(for provider: AIProvider) -> AIProviderSettings {
        providers[provider] ?? AIProviderSettings(apiKey: "", model: "")
    }

    func hasKey(for provider: AIProvider) -> Bool {
        !(providers[provider]?.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    func displayedModel(for provider: AIProvider) -> String {
        provider.canonicalModel(settings(for: provider).model)
    }

    func resolvedModel(for provider: AIProvider) -> String {
        displayedModel(for: provider)
    }

    func taggingRoute() -> AITaggingRoute? {
        taggingRoutes().first
    }

    func taggingRoutes() -> [AITaggingRoute] {
        var order = AIProvider.taggingPriority
        if let selected = selectedProvider, selected.supportsFrameTagging {
            order = [selected] + order.filter { $0 != selected }
        }
        return order.compactMap { provider in
            guard hasKey(for: provider) else { return nil }
            return AITaggingRoute(
                provider: provider,
                apiKey: settings(for: provider).apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                model: resolvedModel(for: provider)
            )
        }
    }
}

struct WarehousePreference: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var path: String
    var bookmark: Data?

    var url: URL {
        URL(fileURLWithPath: path)
    }
}

enum SmartCollection: String, CaseIterable, Identifiable {
    case all
    case tagged
    case untagged
    case missing
    case duplicates

    var id: String { rawValue }

    var localizationKey: String {
        "collection.\(rawValue)"
    }
}

enum SidebarSelection: Hashable {
    case collection(SmartCollection)
    case warehouse(UUID)
    case tagCategory(String)
}
