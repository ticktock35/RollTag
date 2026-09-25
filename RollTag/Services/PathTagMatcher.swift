import Foundation

enum PathTagMatcher {
    static func assignments(
        relativePath: String,
        catalog: TagCatalog,
        customValues: [String],
        blockedCustomKeys: Set<String> = [],
        geocodedPlace: String? = nil
    ) -> [TagAssignment] {
        let segments = folderSegments(relativePath).map(normalize)
        var result: [TagAssignment] = []
        var seen = Set<String>()

        func append(_ tag: TagAssignment) {
            guard seen.insert(tag.identityKey).inserted else { return }
            result.append(tag)
        }

        if !segments.isEmpty, let place = catalog.categories.first(where: { $0.id == "place" }) {
            for tag in place.tags {
                let needles = [tag.id, tag.names["en"], tag.names["zh-Hant"]].compactMap { $0 }
                if needles.contains(where: { matches($0, segments: segments) }) {
                    append(.path(category: place.id, value: tag.id))
                }
            }
        }

        if !segments.isEmpty {
            for value in customValues {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                if AITagSuggester.isBlockedCustom(trimmed, blockedCustomKeys: blockedCustomKeys) {
                    continue
                }
                guard matches(trimmed, segments: segments) else { continue }
                append(.path(category: TagAssignment.customCategory, value: trimmed))
            }
        }

        for tag in geocodeAssignments(geocodedPlace, catalog: catalog) {
            append(tag)
        }
        return result
    }

    static func geocodeAssignments(_ place: String?, catalog: TagCatalog) -> [TagAssignment] {
        var result: [TagAssignment] = []
        var seen = Set<String>()
        for part in geocodeParts(place) {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if trimmed.allSatisfy(\.isNumber) { continue }
            let tag: TagAssignment
            if let placeID = catalogPlaceID(trimmed, catalog: catalog) {
                tag = .path(category: "place", value: placeID)
            } else {
                tag = .path(category: TagAssignment.customCategory, value: trimmed)
            }
            guard seen.insert(tag.identityKey).inserted else { continue }
            result.append(tag)
        }
        return result
    }

    static func inheritableCustoms(
        _ values: [String],
        relativePath: String,
        userCustomKeys: Set<String>
    ) -> [String] {
        let folderKeys = Set(folderSegments(relativePath).map(normalize))
        return values.filter { value in
            let key = KeywordGlossary.lookupKey(value)
            if !key.isEmpty, userCustomKeys.contains(key) {
                return true
            }
            return !folderKeys.contains(normalize(value))
        }
    }

    static func staleFolderNameTags(
        _ tags: [TagAssignment],
        relativePath: String,
        userCustomKeys: Set<String>
    ) -> [TagAssignment] {
        let folderKeys = Set(folderSegments(relativePath).map(normalize))
        return tags.filter { tag in
            guard tag.source == "path", tag.isCustom else { return false }
            let key = KeywordGlossary.lookupKey(tag.value)
            if !key.isEmpty, userCustomKeys.contains(key) {
                return false
            }
            return folderKeys.contains(normalize(tag.value))
        }
    }

    static func matches(_ raw: String, segments: [String]) -> Bool {
        let needle = normalize(raw)
        guard !needle.isEmpty else { return false }
        if containsHan(raw) {
            return segments.contains(needle)
        }
        return segments.contains { $0.contains(needle) }
    }

    static func folderSegments(_ relativePath: String) -> [String] {
        let directory = (relativePath as NSString).deletingLastPathComponent
        guard !directory.isEmpty, directory != "." else { return [] }
        return directory.split(separator: "/").map(String.init).filter { !$0.isEmpty && $0 != "." }
    }

    static func normalize(_ raw: String) -> String {
        let folded = raw.lowercased().folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        return folded.filter { character in
            if character.isWhitespace { return false }
            return !"-_./".contains(character)
        }
    }

    static func geocodeParts(_ raw: String?) -> [String] {
        guard let raw else { return [] }
        return raw
            .split(whereSeparator: { $0 == "," || $0 == "，" || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func catalogPlaceID(_ raw: String, catalog: TagCatalog) -> String? {
        guard let match = StockKeywordExpander.firstCatalogMatch(raw, catalog: catalog),
              match.categoryID == "place"
        else {
            return nil
        }
        return match.tagID
    }

    static func containsHan(_ raw: String) -> Bool {
        raw.unicodeScalars.contains { scalar in
            (0x3400...0x4DBF).contains(scalar.value)
                || (0x4E00...0x9FFF).contains(scalar.value)
                || (0xF900...0xFAFF).contains(scalar.value)
        }
    }
}
