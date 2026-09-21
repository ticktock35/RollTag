import Foundation

struct KeywordPair: Codable, Equatable, Identifiable, Hashable {
    var id: UUID
    var native: String
    var english: String

    init(id: UUID = UUID(), native: String, english: String) {
        self.id = id
        self.native = native
        self.english = english
    }
}

struct KeywordGlossary: Codable, Equatable {
    var pairs: [KeywordPair]

    static var empty: KeywordGlossary { KeywordGlossary(pairs: []) }

    enum CodingKeys: String, CodingKey {
        case pairs
    }

    init(pairs: [KeywordPair]) {
        self.pairs = pairs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pairs = try container.decodeIfPresent([KeywordPair].self, forKey: .pairs) ?? []
    }

    func counterparts(for raw: String) -> [String] {
        let key = Self.lookupKey(raw)
        guard !key.isEmpty else { return [] }
        var result: [String] = []
        var seen = Set<String>()
        func append(_ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let compare = Self.lookupKey(trimmed)
            guard compare != key, seen.insert(compare).inserted else { return }
            result.append(trimmed)
        }
        for pair in pairs {
            if Self.lookupKey(pair.native) == key {
                append(Self.stockForm(pair.english))
            }
            if Self.lookupKey(pair.english) == key {
                append(pair.native.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return result
    }

    func adding(native: String, english: String) -> KeywordGlossary? {
        let nextNative = native.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextEnglish = english.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nextNative.isEmpty, !nextEnglish.isEmpty else { return nil }
        var next = self
        if let index = next.pairs.firstIndex(where: { Self.lookupKey($0.native) == Self.lookupKey(nextNative) }) {
            next.pairs[index].native = nextNative
            next.pairs[index].english = nextEnglish
        } else {
            next.pairs.append(KeywordPair(native: nextNative, english: nextEnglish))
        }
        return next
    }

    func updating(id: UUID, native: String, english: String) -> KeywordGlossary {
        var next = self
        guard let index = next.pairs.firstIndex(where: { $0.id == id }) else { return next }
        let nextNative = native.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextEnglish = english.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nextNative.isEmpty, !nextEnglish.isEmpty else { return next }
        next.pairs[index].native = nextNative
        next.pairs[index].english = nextEnglish
        return next
    }

    func removing(id: UUID) -> KeywordGlossary {
        var next = self
        next.pairs.removeAll { $0.id == id }
        return next
    }

    static func lookupKey(_ raw: String) -> String {
        StockKeywordExpander.stockKeyword(raw)
    }

    static func stockForm(_ raw: String) -> String {
        StockKeywordExpander.stockKeyword(raw)
    }
}
