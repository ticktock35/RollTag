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

    static func localeID(from locale: Locale? = nil, preferred: [String]? = nil) -> String {
        if let locale {
            return mapped(locale.identifier)
        }
        let candidates = preferred ?? Bundle.main.preferredLocalizations
        if let first = candidates.first {
            return mapped(first)
        }
        return mapped(Locale.current.identifier)
    }

    static func mapped(_ raw: String) -> String {
        let id = raw.lowercased().replacingOccurrences(of: "_", with: "-")
        if id == "en" || id.hasPrefix("en-") {
            return "en"
        }
        if id.hasPrefix("zh-hant") || id.hasPrefix("zh-tw") || id.hasPrefix("zh-hk") || id.hasPrefix("zh-mo") {
            return "zh-Hant"
        }
        if id.hasPrefix("zh") {
            return "zh-Hant"
        }
        return "en"
    }
}
