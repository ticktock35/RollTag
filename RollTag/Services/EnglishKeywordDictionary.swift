import Foundation

enum EnglishKeywordDictionary {
    static func englishName(for raw: String) -> String? {
        englishNames(for: raw).first
    }

    static func englishNames(for raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var seen = Set<String>()
        var result: [String] = []
        func append(_ english: String) {
            let formatted = StockKeywordExpander.stockKeyword(english)
            guard !formatted.isEmpty, seen.insert(formatted).inserted else { return }
            result.append(formatted)
        }
        for key in lookupKeys(trimmed) {
            if let english = tables.index[key] {
                append(english)
                return result
            }
        }
        for match in containedMatches(in: trimmed) {
            append(match)
        }
        return result
    }

    static var loadedEntryCount: Int { tables.index.count }

    private struct Tables {
        var index: [String: String]
        var containedByStart: [Character: [String]]
    }

    private static let tables: Tables = buildTables()

    private static func lookupKeys(_ raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var keys = [trimmed]
        let collapsed = StockKeywordExpander.stockKeyword(trimmed)
        if collapsed != trimmed {
            keys.append(collapsed)
        }
        return keys
    }

    private static func containedMatches(in raw: String) -> [String] {
        var english: [String] = []
        var index = raw.startIndex
        while index < raw.endIndex {
            let character = raw[index]
            let remainder = raw[index...]
            var matched: String?
            for key in tables.containedByStart[character] ?? [] {
                if remainder.hasPrefix(key) {
                    matched = key
                    break
                }
            }
            if let matched, let value = tables.index[matched] {
                english.append(value)
                index = raw.index(index, offsetBy: matched.count)
            } else {
                index = raw.index(after: index)
            }
        }
        return english
    }

    private static func buildTables() -> Tables {
        var map: [String: String] = [:]
        let sourceLocales = ["zh-Hant", "zh-Hans", "zh-Hant-TW", "zh-Hant-HK", "ja", "ko"]
        let english = Locale(identifier: "en")

        let regions = Locale.Region.isoRegions.sorted { $0.identifier.count < $1.identifier.count }
        for region in regions {
            let code = region.identifier
            guard code.count == 2, code.allSatisfy(\.isLetter) else { continue }
            guard let en = english.localizedString(forRegionCode: code), !en.isEmpty else { continue }
            guard en.caseInsensitiveCompare(code) != .orderedSame else { continue }
            for localeID in sourceLocales {
                if let name = Locale(identifier: localeID).localizedString(forRegionCode: code) {
                    add(name, english: en, into: &map)
                }
            }
        }

        for code in Locale.isoLanguageCodes {
            guard code.count == 2 || code.count == 3 else { continue }
            guard let en = english.localizedString(forLanguageCode: code), !en.isEmpty else { continue }
            guard en.caseInsensitiveCompare(code) != .orderedSame else { continue }
            for localeID in sourceLocales {
                if let name = Locale(identifier: localeID).localizedString(forLanguageCode: code) {
                    add(name, english: en, into: &map)
                }
            }
        }

        for (source, englishName) in bundledDictionary(named: "CCCEDICTKeywords") {
            add(source, english: englishName, into: &map)
        }
        for (source, englishName) in bundledDictionary(named: "KeywordDictionary") {
            add(source, english: englishName, into: &map, overwrite: true)
        }
        return Tables(index: map, containedByStart: containedIndex(from: map))
    }

    private static func containedIndex(from map: [String: String]) -> [Character: [String]] {
        var grouped: [Character: [String]] = [:]
        for key in map.keys {
            guard (2...6).contains(key.count), let first = key.first else { continue }
            grouped[first, default: []].append(key)
        }
        for (character, keys) in grouped {
            grouped[character] = keys.sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs < rhs
            }
        }
        return grouped
    }

    private static func add(
        _ source: String,
        english: String,
        into map: inout [String: String],
        overwrite: Bool = false
    ) {
        let key = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.count >= 2, StockKeywordExpander.needsEnglishCompanion(key) else { return }
        if overwrite || map[key] == nil {
            map[key] = english
        }
        let collapsed = StockKeywordExpander.stockKeyword(key)
        if collapsed != key, overwrite || map[collapsed] == nil {
            map[collapsed] = english
        }
    }

    private static func bundledDictionary(named name: String) -> [String: String] {
        let bundles = [Bundle.main, Bundle(for: AppModel.self)]
        for bundle in bundles {
            if let url = bundle.url(forResource: name, withExtension: "json"),
               let data = try? Data(contentsOf: url),
               let parsed = try? JSONDecoder().decode([String: String].self, from: data) {
                return parsed
            }
        }
        return [:]
    }
}
