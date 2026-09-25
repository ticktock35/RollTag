import Foundation

struct AITagRef: Codable, Equatable, Hashable {
    var category: String
    var value: String

    var payload: [String: String] {
        ["category": category, "value": value]
    }
}

struct AITaggingExample: Codable, Equatable {
    var ai: [AITagRef]
    var kept: [AITagRef]

    static let maxStored = 8
    static let maxPerConfirm = 3
    static let maxTagsPerSide = 12

    var isCorrection: Bool { Set(ai) != Set(kept) }

    var payload: [String: Any] {
        [
            "ai": ai.map(\.payload),
            "kept": kept.map(\.payload),
        ]
    }

    static func compact(_ tags: [TagAssignment]) -> [AITagRef] {
        var seen = Set<String>()
        var result: [AITagRef] = []
        for tag in tags {
            let category = tag.category.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = tag.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !category.isEmpty, !value.isEmpty else { continue }
            let key = "\(category)/\(value)"
            guard seen.insert(key).inserted else { continue }
            result.append(AITagRef(category: category, value: value))
            if result.count == maxTagsPerSide { break }
        }
        return result
    }

    static func make(ai proposed: [TagAssignment], kept: [TagAssignment]) -> AITaggingExample? {
        let ai = compact(proposed.filter { $0.source == "ai" })
        let kept = compact(kept)
        guard !ai.isEmpty, !kept.isEmpty else { return nil }
        return AITaggingExample(ai: ai, kept: kept)
    }

    static func recording(
        _ existing: [AITaggingExample],
        inserting newest: [AITaggingExample]
    ) -> [AITaggingExample] {
        let ranked = newest.sorted { lhs, rhs in
            if lhs.isCorrection != rhs.isCorrection { return lhs.isCorrection }
            return false
        }
        var next = existing
        for example in ranked.prefix(maxPerConfirm).reversed() {
            next.removeAll { $0 == example }
            next.insert(example, at: 0)
        }
        return Array(next.prefix(maxStored))
    }

    static func payloadList(_ examples: [AITaggingExample]) -> [[String: Any]] {
        examples.prefix(maxStored).map(\.payload)
    }

    static func strippingBlockedCustoms(
        _ examples: [AITaggingExample],
        blockedCustomKeys: Set<String>
    ) -> [AITaggingExample] {
        guard !blockedCustomKeys.isEmpty else { return examples }
        return examples.compactMap { example in
            let ai = example.ai.filter { !isBlockedCustom($0, blockedCustomKeys: blockedCustomKeys) }
            let kept = example.kept.filter { !isBlockedCustom($0, blockedCustomKeys: blockedCustomKeys) }
            guard !ai.isEmpty, !kept.isEmpty else { return nil }
            return AITaggingExample(ai: ai, kept: kept)
        }
    }

    private static func isBlockedCustom(_ tag: AITagRef, blockedCustomKeys: Set<String>) -> Bool {
        guard tag.category == TagAssignment.customCategory else { return false }
        let key = KeywordGlossary.lookupKey(tag.value)
        return !key.isEmpty && blockedCustomKeys.contains(key)
    }
}
