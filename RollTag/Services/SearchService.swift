import Foundation

enum SearchService {
    struct Context: Equatable {
        var warehouseName: String
        var warehousePath: String
        var isOnline: Bool
    }

    static func tokenize(_ raw: String) -> [String] {
        raw
            .replacingOccurrences(of: "，", with: " ")
            .replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    static func expandSearchTokens(
        _ tokens: [String],
        catalog: TagCatalog,
        glossary: KeywordGlossary = .empty
    ) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        func append(_ raw: String) {
            let token = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !token.isEmpty, seen.insert(token).inserted else { return }
            result.append(token)
        }
        for token in tokens {
            append(token)
            for alias in StockKeywordExpander.searchAliases(for: token, catalog: catalog, glossary: glossary) {
                append(alias)
            }
        }
        return result
    }

    static func score(footage: Footage, tokens: [String], catalog: TagCatalog, locale _: String) -> Double {
        guard !tokens.isEmpty else { return 1 }
        var total = 0.0
        for token in tokens {
            total += tokenScore(footage: footage, token: token, catalog: catalog)
        }
        return total
    }

    static func rank(
        query: String,
        items: [(Footage, Context)],
        catalog: TagCatalog,
        locale: String = TagCatalogLoader.localeID(),
        glossary: KeywordGlossary = .empty
    ) -> [ScoredFootage] {
        let tokens = expandSearchTokens(tokenize(query), catalog: catalog, glossary: glossary)
        var scored: [ScoredFootage] = []

        for (footage, context) in items {
            if footage.status == .available, !context.isOnline { continue }
            let value = tokens.isEmpty ? 1.0 : score(footage: footage, tokens: tokens, catalog: catalog, locale: locale)
            if !tokens.isEmpty, value <= 0 { continue }
            scored.append(
                ScoredFootage(
                    footage: footage,
                    score: value,
                    warehouseName: context.warehouseName,
                    warehousePath: context.warehousePath,
                    isOnline: context.isOnline
                )
            )
        }

        scored.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if let leftHash = lhs.footage.phash, let rightHash = rhs.footage.phash, leftHash != rightHash {
                return leftHash < rightHash
            }
            return lhs.footage.filename.localizedCaseInsensitiveCompare(rhs.footage.filename) == .orderedAscending
        }

        if tokens.isEmpty { return scored }
        return applyPhashNudge(scored)
    }

    static func ordered(_ items: [ScoredFootage], sort: LibrarySort, ascending: Bool) -> [ScoredFootage] {
        items.sorted { lhs, rhs in
            if let decided = compare(lhs, rhs, sort: sort, ascending: ascending) {
                return decided
            }
            let name = lhs.footage.filename.localizedStandardCompare(rhs.footage.filename)
            if name != .orderedSame {
                return name == .orderedAscending
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private static func compare(
        _ lhs: ScoredFootage,
        _ rhs: ScoredFootage,
        sort: LibrarySort,
        ascending: Bool
    ) -> Bool? {
        switch sort {
        case .relevance:
            return compareValues(lhs.score, rhs.score, ascending: ascending)
        case .filename:
            let order = lhs.footage.filename.localizedStandardCompare(rhs.footage.filename)
            guard order != .orderedSame else { return nil }
            return ascending ? order == .orderedAscending : order == .orderedDescending
        case .capturedAt:
            return compareOptionals(lhs.footage.capturedAt, rhs.footage.capturedAt, ascending: ascending)
        case .modified:
            return compareValues(lhs.footage.mtime, rhs.footage.mtime, ascending: ascending)
        case .duration:
            return compareOptionals(lhs.footage.duration, rhs.footage.duration, ascending: ascending)
        case .size:
            return compareValues(lhs.footage.size, rhs.footage.size, ascending: ascending)
        case .kind:
            return compareValues(kindOrder(lhs.footage.mediaKind), kindOrder(rhs.footage.mediaKind), ascending: ascending)
        }
    }

    private static func kindOrder(_ kind: MediaKind) -> Int {
        switch kind {
        case .video: return 0
        case .image: return 1
        case .audio: return 2
        }
    }

    private static func compareValues<T: Comparable>(_ lhs: T, _ rhs: T, ascending: Bool) -> Bool? {
        guard lhs != rhs else { return nil }
        return ascending ? lhs < rhs : lhs > rhs
    }

    private static func compareOptionals<T: Comparable>(_ lhs: T?, _ rhs: T?, ascending: Bool) -> Bool? {
        switch (lhs, rhs) {
        case (nil, nil):
            return nil
        case (nil, _):
            return false
        case (_, nil):
            return true
        case let (left?, right?):
            return compareValues(left, right, ascending: ascending)
        }
    }

    private static func tokenScore(footage: Footage, token: String, catalog: TagCatalog) -> Double {
        var best = 0.0

        for tag in footage.tags {
            let tagValue = tag.value.lowercased()
            if tagValue == token { best = max(best, 100) }
            if tag.isCustom, tagValue.contains(token) { best = max(best, 90) }
            if let category = catalog.categories.first(where: { $0.id == tag.category }) {
                if tag.category.lowercased() == token {
                    best = max(best, 40)
                }
                for name in category.names.values where name.lowercased() == token {
                    best = max(best, 40)
                }
                if let definition = category.tags.first(where: { $0.id == tag.value }) {
                    if definition.id.lowercased() == token { best = max(best, 100) }
                    for name in definition.names.values {
                        let localized = name.lowercased()
                        if localized == token { best = max(best, 100) }
                        if localized.contains(token) { best = max(best, 70) }
                    }
                    if let english = StockKeywordExpander.englishStockKeyword(
                        category: category.id,
                        value: tag.value,
                        catalog: catalog
                    ), english == token {
                        best = max(best, 100)
                    }
                }
            }
        }

        if footage.filename.lowercased().contains(token) { best = max(best, 30) }
        if footage.relativePath.lowercased().contains(token) { best = max(best, 20) }
        if footage.userNotes.lowercased().contains(token) { best = max(best, 15) }

        if let captured = footage.capturedAt {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy"
            if formatter.string(from: captured) == token { best = max(best, 25) }
        }

        return best
    }

    private static func applyPhashNudge(_ items: [ScoredFootage]) -> [ScoredFootage] {
        guard let top = items.first, let seed = top.footage.phash, !seed.isEmpty else { return items }
        return items.map { item in
            guard let hash = item.footage.phash, hash != seed else { return item }
            let distance = hamming(seed, hash)
            guard distance <= 8 else { return item }
            var next = item
            next.score += max(0, 8 - Double(distance))
            return next
        }
        .sorted { $0.score > $1.score }
    }

    static func hamming(_ lhs: String, _ rhs: String) -> Int {
        zip(lhs, rhs).reduce(0) { $1.0 == $1.1 ? $0 : $0 + 1 }
    }
}
