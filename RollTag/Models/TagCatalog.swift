import Foundation

struct TagCatalog: Codable, Equatable {
    var categories: [TagCategory]
}

struct TagCategory: Codable, Identifiable, Hashable {
    var id: String
    var names: [String: String]
    var tags: [TagDefinition]

    func localizedName(locale: String) -> String {
        names[locale] ?? names["en"] ?? id
    }
}

struct TagDefinition: Codable, Identifiable, Hashable {
    var id: String
    var names: [String: String]

    func localizedName(locale: String) -> String {
        names[locale] ?? names["en"] ?? id
    }
}

enum TagCatalogLoader {
    static func load(from bundle: Bundle = .main) -> TagCatalog {
        guard let url = bundle.url(forResource: "DefaultTags", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(TagCatalog.self, from: data)
        else {
            return TagCatalog(categories: [])
        }
        return catalog
    }

    static func localeID(from locale: Locale = .current) -> String {
        if locale.identifier.lowercased().hasPrefix("zh-hant") || locale.identifier.hasPrefix("zh_TW") || locale.identifier.hasPrefix("zh-TW") {
            return "zh-Hant"
        }
        if locale.language.languageCode?.identifier == "zh" {
            let script = locale.language.script?.identifier
            if script == "Hant" { return "zh-Hant" }
        }
        return locale.language.languageCode?.identifier == "zh" ? "zh-Hant" : "en"
    }
}
