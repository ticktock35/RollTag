import Foundation

enum StockKeywordExpander {
    static func expand(
        _ tags: [TagAssignment],
        catalog: TagCatalog,
        includeEnglishKeywords: Bool,
        glossary: KeywordGlossary = .empty
    ) -> [TagAssignment] {
        var result: [TagAssignment] = []
        for tag in tags {
            result.append(
                contentsOf: expansions(
                    for: tag,
                    catalog: catalog,
                    includeEnglishKeywords: includeEnglishKeywords,
                    glossary: glossary
                )
            )
        }
        return TagAssignment.uniqued(result)
    }

    static func expansions(
        for tag: TagAssignment,
        catalog: TagCatalog,
        includeEnglishKeywords: Bool,
        glossary: KeywordGlossary = .empty
    ) -> [TagAssignment] {
        var result = [tag]
        if tag.isCustom {
            let counterparts = glossary.counterparts(for: tag.value)
            for word in counterparts {
                appendCustom(word, source: tag.source, to: &result)
            }
            let hasLatinCompanion = counterparts.contains { !needsEnglishCompanion($0) }
                || !needsEnglishCompanion(tag.value)

            if let match = firstCatalogMatch(tag.value, catalog: catalog) {
                result.append(TagAssignment(category: match.categoryID, value: match.tagID, source: tag.source))
                let english = stockKeyword(match.englishName)
                if !english.isEmpty, !equalsIgnoringCase(english, tag.value) {
                    appendCustom(english, source: tag.source, to: &result)
                }
            } else if !hasLatinCompanion, needsEnglishCompanion(tag.value) {
                let englishKeywords = dictionaryEnglishKeywords(tag.value)
                if !englishKeywords.isEmpty {
                    for english in englishKeywords {
                        appendCustom(english, source: tag.source, to: &result)
                    }
                } else if let english = romanizedStockKeyword(tag.value) {
                    appendCustom(english, source: tag.source, to: &result)
                }
            }
        } else if includeEnglishKeywords, let english = englishStockKeyword(category: tag.category, value: tag.value, catalog: catalog) {
            appendCustom(english, source: tag.source, to: &result)
        }
        return TagAssignment.uniqued(result)
    }

    static func stockKeyword(_ raw: String) -> String {
        let trimmed = raw
            .replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let collapsed = trimmed.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return collapsed
    }

    static func needsEnglishCompanion(_ text: String) -> Bool {
        text.unicodeScalars.contains { CharacterSet.letters.contains($0) && !$0.isASCII }
    }

    static func searchAliases(
        for token: String,
        catalog: TagCatalog,
        glossary: KeywordGlossary = .empty
    ) -> [String] {
        var aliases = glossary.counterparts(for: token)
        let hasLatinCompanion = aliases.contains { !needsEnglishCompanion($0) }
        if needsEnglishCompanion(token) {
            if let match = firstCatalogMatch(token, catalog: catalog) {
                aliases.append(stockKeyword(match.englishName))
                aliases.append(match.tagID.lowercased())
            } else if !hasLatinCompanion {
                let englishKeywords = dictionaryEnglishKeywords(token)
                if !englishKeywords.isEmpty {
                    aliases.append(contentsOf: englishKeywords)
                } else if let romanized = romanizedStockKeyword(token) {
                    aliases.append(romanized)
                }
            }
        }
        var seen = Set<String>()
        return aliases.filter { alias in
            !alias.isEmpty && alias != stockKeyword(token) && seen.insert(alias).inserted
        }
    }

    private static func appendCustom(_ value: String, source: String, to result: inout [TagAssignment]) {
        guard let custom = TagAssignment.custom(value) else { return }
        result.append(TagAssignment(category: custom.category, value: custom.value, source: source))
    }

    static func firstCatalogMatch(_ raw: String, catalog: TagCatalog) -> (categoryID: String, tagID: String, englishName: String)? {
        let key = stockKeyword(raw)
        guard !key.isEmpty else { return nil }
        for category in catalog.categories {
            for tag in category.tags {
                let names = [tag.id] + Array(tag.names.values)
                if names.contains(where: { stockKeyword($0) == key }) {
                    return (category.id, tag.id, tag.localizedName(locale: "en"))
                }
            }
        }
        return nil
    }

    static func englishStockKeyword(category: String, value: String, catalog: TagCatalog) -> String? {
        guard let group = catalog.categories.first(where: { $0.id == category }),
              let tag = group.tags.first(where: { $0.id == value })
        else { return nil }
        let formatted = stockKeyword(tag.localizedName(locale: "en"))
        return formatted.isEmpty ? nil : formatted
    }

    static func dictionaryEnglishKeyword(_ raw: String) -> String? {
        EnglishKeywordDictionary.englishName(for: raw)
    }

    static func dictionaryEnglishKeywords(_ raw: String) -> [String] {
        EnglishKeywordDictionary.englishNames(for: raw)
    }

    static func romanizedStockKeyword(_ text: String) -> String? {
        let ns = text as NSString
        guard let latin = ns.applyingTransform(.toLatin, reverse: false) else { return nil }
        let plain = (latin as NSString).applyingTransform(.stripDiacritics, reverse: false) ?? latin
        let formatted = stockKeyword(plain)
        guard !formatted.isEmpty, formatted != stockKeyword(text) else { return nil }
        return formatted
    }

    static func gettyKeyword(_ raw: String) -> String? {
        let formatted = stockKeyword(raw)
        guard (3...40).contains(formatted.count) else { return nil }
        let words = formatted.split(whereSeparator: \.isWhitespace).map(String.init)
        guard (1...5).contains(words.count), !needsEnglishCompanion(formatted) else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        for word in words {
            guard !word.isEmpty, word.unicodeScalars.allSatisfy({ $0.isASCII && allowed.contains($0) }) else {
                return nil
            }
        }
        return formatted
    }

    static func isVisibleCustomLabel(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...16).contains(value.count), !value.contains(where: \.isNewline) else { return false }
        return needsEnglishCompanion(value)
    }

    private static func equalsIgnoringCase(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}
