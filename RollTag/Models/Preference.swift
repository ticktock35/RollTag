import Foundation

struct PreferenceFile: Codable, Equatable {
    var version: Int
    var warehouses: [WarehousePreference]
    var ai: AIPreference
    var shortcuts: ShortcutPreference
    var glossary: KeywordGlossary
    var recentCustomTags: [String]
    var invertTwoFingerPan: Bool
    var primaryDisplayID: UInt32?
    var fontSizeStep: Int

    static let currentVersion = 1

    enum CodingKeys: String, CodingKey {
        case version
        case warehouses
        case ai
        case shortcuts
        case glossary
        case recentCustomTags
        case invertTwoFingerPan
        case primaryDisplayID
        case fontSizeStep
    }

    static var empty: PreferenceFile {
        PreferenceFile(version: currentVersion, warehouses: [], ai: .empty, shortcuts: .empty, glossary: .empty, invertTwoFingerPan: false, primaryDisplayID: nil, fontSizeStep: AppFontSize.defaultStep)
    }

    init(
        version: Int,
        warehouses: [WarehousePreference],
        ai: AIPreference = .empty,
        shortcuts: ShortcutPreference = .empty,
        glossary: KeywordGlossary = .empty,
        recentCustomTags: [String] = [],
        invertTwoFingerPan: Bool = false,
        primaryDisplayID: UInt32? = nil,
        fontSizeStep: Int = AppFontSize.defaultStep
    ) {
        self.version = version
        self.warehouses = warehouses
        self.ai = ai
        self.shortcuts = shortcuts
        self.glossary = glossary
        self.recentCustomTags = recentCustomTags
        self.invertTwoFingerPan = invertTwoFingerPan
        self.primaryDisplayID = primaryDisplayID
        self.fontSizeStep = AppFontSize.clamped(fontSizeStep)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? PreferenceFile.currentVersion
        warehouses = try container.decodeIfPresent([WarehousePreference].self, forKey: .warehouses) ?? []
        if let decodedAI = try container.decodeIfPresent(AIPreference.self, forKey: .ai) {
            ai = decodedAI
        } else if let flatAI = try? AIPreference(from: decoder) {
            ai = flatAI
        } else {
            ai = .empty
        }
        shortcuts = try container.decodeIfPresent(ShortcutPreference.self, forKey: .shortcuts) ?? .empty
        glossary = try container.decodeIfPresent(KeywordGlossary.self, forKey: .glossary) ?? .empty
        recentCustomTags = try container.decodeIfPresent([String].self, forKey: .recentCustomTags) ?? []
        invertTwoFingerPan = try container.decodeIfPresent(Bool.self, forKey: .invertTwoFingerPan) ?? false
        if let storedID = try container.decodeIfPresent(UInt32.self, forKey: .primaryDisplayID), storedID != 0 {
            primaryDisplayID = storedID
        } else {
            primaryDisplayID = nil
        }
        fontSizeStep = AppFontSize.clamped(
            try container.decodeIfPresent(Int.self, forKey: .fontSizeStep) ?? AppFontSize.defaultStep
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(warehouses, forKey: .warehouses)
        try container.encode(ai, forKey: .ai)
        if shortcuts != .empty {
            try container.encode(shortcuts, forKey: .shortcuts)
        }
        if glossary != .empty {
            try container.encode(glossary, forKey: .glossary)
        }
        if !recentCustomTags.isEmpty {
            try container.encode(recentCustomTags, forKey: .recentCustomTags)
        }
        if invertTwoFingerPan {
            try container.encode(invertTwoFingerPan, forKey: .invertTwoFingerPan)
        }
        if let primaryDisplayID {
            try container.encode(primaryDisplayID, forKey: .primaryDisplayID)
        }
        let step = AppFontSize.clamped(fontSizeStep)
        if step != AppFontSize.defaultStep {
            try container.encode(step, forKey: .fontSizeStep)
        }
    }
}

enum LocalAIScheme: String, CaseIterable, Identifiable, Codable {
    case appleVision = "apple_vision"
    case florence2Base = "florence2_base"
    case ramPlus = "ram_plus"

    var id: String { rawValue }

    var provider: AIProvider {
        switch self {
        case .appleVision: return .appleVision
        case .florence2Base: return .florence2Base
        case .ramPlus: return .ramPlus
        }
    }

    var defaultModel: String { rawValue }

    var title: String {
        switch self {
        case .appleVision: return "Apple Vision"
        case .florence2Base: return "MS Florence-2 Base"
        case .ramPlus: return "RAM++"
        }
    }

    var detail: String {
        switch self {
        case .appleVision:
            return String(localized: "settings.ai.local.scheme.apple_vision.desc")
        case .florence2Base:
            return String(localized: "settings.ai.local.scheme.florence2_base.desc")
        case .ramPlus:
            return String(localized: "settings.ai.local.scheme.ram_plus.desc")
        }
    }
}

enum AIProvider: String, CaseIterable, Identifiable, Codable, Hashable {
    case appleVision = "apple_vision"
    case florence2Base = "florence2_base"
    case ramPlus = "ram_plus"
    case gemini
    case openai
    case twelvelabs
    case dashscope
    case anthropic

    var id: String { rawValue }

    var isLocal: Bool {
        self == .appleVision || self == .florence2Base || self == .ramPlus
    }

    var localizationKey: String { "ai.provider.\(rawValue)" }
    var capabilityKey: String { "ai.capability.\(rawValue)" }

    var usageURL: URL? {
        switch self {
        case .gemini:
            URL(string: "https://aistudio.google.com/usage")
        case .openai:
            URL(string: "https://platform.openai.com/usage")
        default:
            nil
        }
    }

    var infoURL: URL? { nil }

    static let taggingPriority: [AIProvider] = [.gemini, .openai]

    static var cloudProviders: [AIProvider] { [.gemini, .openai] }

    static var keyedProviders: [AIProvider] { allCases.filter(\.needsAPIKey) }

    var needsAPIKey: Bool { !isLocal }

    var supportsFrameTagging: Bool {
        isLocal || self == .gemini || self == .openai
    }

    var selectableModels: [String] {
        switch self {
        case .gemini:
            ["gemini-3.5-flash-lite", "gemini-3.1-flash-lite", "gemini-3.5-flash", "gemini-3.8-flash"]
        case .openai:
            ["gpt-4.1-mini", "gpt-4.1", "gpt-4o"]
        case .appleVision:
            ["apple_vision"]
        case .florence2Base:
            ["florence2_base"]
        case .ramPlus:
            ["ram_plus"]
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
    var localAIEnabled: Bool
    var localAIScheme: LocalAIScheme
    var activeCloudPlatform: AIProvider?
    var geminiApiKey: String
    var geminiModel: String
    var openaiApiKey: String
    var openaiModel: String
    var skipImplausibleCaptureDates: Bool
    var examples: [AITaggingExample]

    enum CodingKeys: String, CodingKey {
        case localAIEnabled
        case localAIScheme
        case activeCloudPlatform
        case geminiApiKey
        case geminiModel
        case openaiApiKey
        case openaiModel
        case skipImplausibleCaptureDates
        case examples

        // Legacy compatibility keys
        case useJoyTag
        case selectedProvider
        case providers
    }

    static var empty: AIPreference {
        AIPreference(
            localAIEnabled: true,
            localAIScheme: .appleVision,
            activeCloudPlatform: .gemini,
            geminiApiKey: "",
            geminiModel: "gemini-3.5-flash-lite",
            openaiApiKey: "",
            openaiModel: "gpt-4.1-mini",
            skipImplausibleCaptureDates: true,
            examples: []
        )
    }

    init(
        localAIEnabled: Bool = true,
        localAIScheme: LocalAIScheme = .appleVision,
        activeCloudPlatform: AIProvider? = .gemini,
        geminiApiKey: String = "",
        geminiModel: String = "gemini-3.5-flash-lite",
        openaiApiKey: String = "",
        openaiModel: String = "gpt-4.1-mini",
        skipImplausibleCaptureDates: Bool = true,
        examples: [AITaggingExample] = []
    ) {
        self.localAIEnabled = localAIEnabled
        self.localAIScheme = localAIScheme
        self.activeCloudPlatform = activeCloudPlatform
        self.geminiApiKey = geminiApiKey
        self.geminiModel = geminiModel.isEmpty ? "gemini-3.5-flash-lite" : geminiModel
        self.openaiApiKey = openaiApiKey
        self.openaiModel = openaiModel.isEmpty ? "gpt-4.1-mini" : openaiModel
        self.skipImplausibleCaptureDates = skipImplausibleCaptureDates
        self.examples = examples
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let legacySelectedRaw = try container.decodeIfPresent(String.self, forKey: .selectedProvider)

        if let enabled = try container.decodeIfPresent(Bool.self, forKey: .localAIEnabled) {
            localAIEnabled = enabled
        } else if let joyTag = try container.decodeIfPresent(Bool.self, forKey: .useJoyTag) {
            localAIEnabled = joyTag
        } else if legacySelectedRaw == "joytag" {
            localAIEnabled = true
        } else {
            localAIEnabled = true
        }

        localAIScheme = try container.decodeIfPresent(LocalAIScheme.self, forKey: .localAIScheme) ?? .appleVision

        if let active = try container.decodeIfPresent(AIProvider.self, forKey: .activeCloudPlatform) {
            activeCloudPlatform = active.isLocal ? nil : active
        } else if let legacySelectedRaw {
            if legacySelectedRaw == "joytag" {
                activeCloudPlatform = nil
            } else if let selected = AIProvider(rawValue: legacySelectedRaw) {
                activeCloudPlatform = selected.isLocal ? nil : selected
            } else {
                activeCloudPlatform = nil
            }
        } else {
            activeCloudPlatform = .gemini
        }

        let legacyProviders = try container.decodeIfPresent([AIProvider: AIProviderSettings].self, forKey: .providers) ?? [:]

        let gKey = try container.decodeIfPresent(String.self, forKey: .geminiApiKey)
            ?? legacyProviders[.gemini]?.apiKey ?? ""
        let gModel = try container.decodeIfPresent(String.self, forKey: .geminiModel)
            ?? legacyProviders[.gemini]?.model ?? "gemini-3.5-flash-lite"
        geminiApiKey = gKey
        geminiModel = gModel.isEmpty ? "gemini-3.5-flash-lite" : gModel

        let oKey = try container.decodeIfPresent(String.self, forKey: .openaiApiKey)
            ?? legacyProviders[.openai]?.apiKey ?? ""
        let oModel = try container.decodeIfPresent(String.self, forKey: .openaiModel)
            ?? legacyProviders[.openai]?.model ?? "gpt-4.1-mini"
        openaiApiKey = oKey
        openaiModel = oModel.isEmpty ? "gpt-4.1-mini" : oModel

        skipImplausibleCaptureDates = try container.decodeIfPresent(Bool.self, forKey: .skipImplausibleCaptureDates) ?? true
        examples = try container.decodeIfPresent([AITaggingExample].self, forKey: .examples) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(localAIEnabled, forKey: .localAIEnabled)
        try container.encode(localAIScheme, forKey: .localAIScheme)
        if let activeCloudPlatform {
            try container.encode(activeCloudPlatform, forKey: .activeCloudPlatform)
        }
        if !geminiApiKey.isEmpty {
            try container.encode(geminiApiKey, forKey: .geminiApiKey)
        }
        try container.encode(geminiModel, forKey: .geminiModel)
        if !openaiApiKey.isEmpty {
            try container.encode(openaiApiKey, forKey: .openaiApiKey)
        }
        try container.encode(openaiModel, forKey: .openaiModel)
        try container.encode(skipImplausibleCaptureDates, forKey: .skipImplausibleCaptureDates)
        if !examples.isEmpty {
            try container.encode(examples, forKey: .examples)
        }
    }

    // Legacy compatibility properties
    var selectedProvider: AIProvider? {
        get { activeCloudPlatform }
        set { activeCloudPlatform = newValue?.isLocal == true ? nil : newValue }
    }

    var useJoyTag: Bool {
        get { localAIEnabled }
        set { localAIEnabled = newValue }
    }

    var providers: [AIProvider: AIProviderSettings] {
        get {
            var result: [AIProvider: AIProviderSettings] = [:]
            if !geminiApiKey.isEmpty || !geminiModel.isEmpty {
                result[.gemini] = AIProviderSettings(apiKey: geminiApiKey, model: geminiModel)
            }
            if !openaiApiKey.isEmpty || !openaiModel.isEmpty {
                result[.openai] = AIProviderSettings(apiKey: openaiApiKey, model: openaiModel)
            }
            return result
        }
        set {
            if let gemini = newValue[.gemini] {
                geminiApiKey = gemini.apiKey
                geminiModel = gemini.model
            }
            if let openai = newValue[.openai] {
                openaiApiKey = openai.apiKey
                openaiModel = openai.model
            }
        }
    }

    func settings(for provider: AIProvider) -> AIProviderSettings {
        switch provider {
        case .gemini:
            return AIProviderSettings(apiKey: geminiApiKey, model: geminiModel)
        case .openai:
            return AIProviderSettings(apiKey: openaiApiKey, model: openaiModel)
        default:
            return AIProviderSettings(apiKey: "", model: provider.defaultModel)
        }
    }

    func hasKey(for provider: AIProvider) -> Bool {
        switch provider {
        case .gemini:
            return !geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .openai:
            return !openaiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            return provider.isLocal
        }
    }

    func apiKey(for provider: AIProvider) -> String {
        switch provider {
        case .gemini:
            return geminiApiKey
        case .openai:
            return openaiApiKey
        default:
            return ""
        }
    }

    func displayedModel(for provider: AIProvider) -> String {
        switch provider {
        case .gemini:
            return provider.canonicalModel(geminiModel)
        case .openai:
            return provider.canonicalModel(openaiModel)
        default:
            return provider.defaultModel
        }
    }

    func resolvedModel(for provider: AIProvider) -> String {
        displayedModel(for: provider)
    }

    func taggingRoute() -> AITaggingRoute? {
        taggingRoutes().first
    }

    func cloudTaggingRoutes() -> [AITaggingRoute] {
        var routes: [AITaggingRoute] = []
        var cloudOrder = AIProvider.taggingPriority
        if let active = activeCloudPlatform, active.needsAPIKey {
            cloudOrder = [active] + cloudOrder.filter { $0 != active }
        }
        for provider in cloudOrder where hasKey(for: provider) {
            routes.append(
                AITaggingRoute(
                    provider: provider,
                    apiKey: apiKey(for: provider).trimmingCharacters(in: .whitespacesAndNewlines),
                    model: resolvedModel(for: provider)
                )
            )
        }
        return routes
    }

    func taggingRoutes(overrideLocalScheme: LocalAIScheme? = nil, skipLocalAI: Bool = false) -> [AITaggingRoute] {
        var routes: [AITaggingRoute] = []
        if !skipLocalAI && localAIEnabled {
            let scheme = overrideLocalScheme ?? localAIScheme
            routes.append(
                AITaggingRoute(
                    provider: scheme.provider,
                    apiKey: "",
                    model: scheme.defaultModel
                )
            )
        }
        routes.append(contentsOf: cloudTaggingRoutes())
        return routes
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
    /// Relative folder inside a warehouse. Search and the grid stay inside this folder and its descendants.
    case warehouseFolder(UUID, String)
    /// Imported GPX filename inside a warehouse. Grid shows files whose folder is assigned to this track and whose time falls in the span.
    case gpx(UUID, String)
    case tagCategory(String)
}

struct FolderRef: Hashable, Identifiable, Sendable {
    var warehouseID: UUID
    var relativePath: String

    var id: String { "\(warehouseID.uuidString)/\(relativePath)" }

    var folderName: String {
        (relativePath as NSString).lastPathComponent
    }
}
