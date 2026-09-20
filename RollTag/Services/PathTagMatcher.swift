import Foundation

enum PathTagMatcher {
    static func assignments(
        relativePath: String,
        catalog: TagCatalog,
        customValues: [String]
    ) -> [TagAssignment] {
        let segments = folderSegments(relativePath).map(normalize)
        guard !segments.isEmpty else { return [] }

        var result: [TagAssignment] = []
        var seen = Set<String>()

        if let place = catalog.categories.first(where: { $0.id == "place" }) {
            for tag in place.tags {
                let needles = [tag.id, tag.names["en"], tag.names["zh-Hant"]].compactMap { $0 }
                if needles.contains(where: { matches($0, segments: segments) }) {
                    let assignment = TagAssignment.path(category: place.id, value: tag.id)
                    if seen.insert(assignment.identityKey).inserted {
                        result.append(assignment)
                    }
                }
            }
        }

        for value in customValues {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, matches(trimmed, segments: segments) else { continue }
            let assignment = TagAssignment.path(category: TagAssignment.customCategory, value: trimmed)
            if seen.insert(assignment.identityKey).inserted {
                result.append(assignment)
            }
        }
        return result
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

    static func containsHan(_ raw: String) -> Bool {
        raw.unicodeScalars.contains { scalar in
            (0x3400...0x4DBF).contains(scalar.value)
                || (0x4E00...0x9FFF).contains(scalar.value)
                || (0xF900...0xFAFF).contains(scalar.value)
        }
    }
}
