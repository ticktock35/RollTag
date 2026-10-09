import Foundation

enum AITagError: LocalizedError, Equatable {
    case missingAPIKey
    case missingFrames
    case unsupportedProvider
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "missing_api_key"
        case .missingFrames:
            "missing_frames"
        case .unsupportedProvider:
            "unsupported_provider"
        case .requestFailed(let message):
            message
        }
    }
}

enum AITagSuggest {
    static let geminiFrameLimit = 3
    static let retryableStatus: Set<Int> = [429, 500, 502, 503]
    static let defaultGeminiModel = "gemini-3.5-flash-lite"
    static let defaultOpenAIModel = "gpt-4.1-mini"

    static let prompt = """
    You tag B-roll stills for a footage warehouse.
    Choose 3 to 8 tags that clearly match the frames.
    Use only category and value ids from the catalog JSON for "tags". Never invent catalog ids.
    Custom tags (category "custom") may only name an object or sign that is clearly readable in THESE frames (a vessel, product, landmark text). Do not invent personal names. Do not apply a person's name from filename, folder, GPS, place, EXAMPLES, or other clips. Seeing a person is not enough. If unsure who it is, omit the name.
    If CONTEXT is present, use filename, path, warehouse name, duration, file size, capture time, GPS, and place as hints for place and time tags. The place field is a reverse-geocoded locality from the file GPS. Folder and path names are hints only — never copy a folder name as a custom tag. The app writes CONTEXT.place parts (locality, region, country) as custom tags. Still add catalog place types that match (city, nature, rural, forest, ocean) when the location or frames support them. Frames remain primary. Do not turn a place hint into a person's name. Do not tag month or weekday names from captured_at (no march, friday).
    If CONTEXT.vision is present, it is on-device Vision from this Mac (faces, bodies, hands, scene labels, animals, readable text). Treat people, people_count, hands, and face as facts:
    - Set the people count tag to match vision.people. Do not override it from filename, folder, or guesses.
    - If vision.people is none: use people/none only. Do not add portrait, distant, age, hands, or people keywords other than "no people".
    - people/portrait only if vision.face is portrait. people/distant only if vision.face is distant.
    - If vision.hands is true and people is not none, people/hands may apply.
    - scenes and animals are hints, not catalog ids. Confirm them in the frames before tagging.
    - If vision.animals is present and vision.people is none, those detections are live animals (dogs, cats), not humans. Do not add people tags or personal names.
    - text is OCR of signs; a short readable token may become a custom tag. Do not treat OCR as a person's name.

    People count is mandatory and must be exact:
    - Look at every frame. Count only distinct living humans you can see (body or hands). Ignore statues, posters, mannequins, reflections, drawings, and maybe-shapes.
    - Plush toys, stuffed animals, figurines, and dolls are not living humans and not live animals. Do not tag people/*, animals/pet, or an animal species for a toy.
    - Always include exactly one of people/none, people/one, people/two, people/group, or people/crowd.
    - people/none: no human in any frame. Default when unsure. Do not add portrait, crowd, distant, age tags, or keywords such as people, person, man, woman, crowd.
    - people/one: exactly one person. Not group. Not crowd.
    - people/two: exactly two people. Not one. Not group.
    - people/group: about 3 to 10 people, not a dense crowd.
    - people/crowd: many people filling the scene.
    - people/portrait only if a face is the main subject. people/distant only if humans are small in the frame.
    - Filename must not invent people.

    Also return Getty/Pond5 English keywords in "keywords":
    - lowercase, words separated by single spaces, no hashtags, no camelCase, no sentences
    - 6 to 20 phrases, 1 to 5 words each
    - include English for every non-English subject you name (icebreaker, not pinyin)
    - use the catalog "en" names when they match what you see
    - include no people, one person, or two people when that is what you see
    - visible nouns, place, weather, people, shot; suitable for stock-footage search

    If EXAMPLES are present, they are recent human outcomes: "ai" is what the model tagged, "kept" is what the user left after editing. Follow kept wording only when the current frames show the same subject. Do not copy personal names or custom labels onto unrelated scenes. Frames remain primary.

    Return JSON: {"tags":[{"category":"...","value":"..."}],"keywords":["icebreaker","arctic ocean"]}

    CATALOG:
    """

    static func buildPrompt(
        catalog: [String: Any],
        context: [String: Any]? = nil,
        examples: [[String: Any]]? = nil
    ) -> String {
        var prompt = Self.prompt + CompactJSON.stringify(catalog)
        let cleaned = normalizeExamples(examples)
        if !cleaned.isEmpty {
            prompt += "\n\nEXAMPLES:\n" + CompactJSON.stringify(cleaned)
        }
        if let context, !context.isEmpty {
            prompt += "\n\nCONTEXT:\n" + CompactJSON.stringify(context)
        }
        return prompt
    }

    static func parseTags(_ text: String) -> [AITagRef] {
        guard let data = parseJSON(text) else { return [] }
        let items: [Any]
        if let object = data as? [String: Any] {
            items = object["tags"] as? [Any] ?? []
        } else if let list = data as? [Any] {
            items = list
        } else {
            return []
        }
        var tags: [AITagRef] = []
        var seen = Set<String>()
        for item in items {
            guard let object = item as? [String: Any] else { continue }
            let category = stringValue(object["category"])
            let value = stringValue(object["value"])
            guard !category.isEmpty, !value.isEmpty else { continue }
            let key = "\(category)/\(value)"
            guard seen.insert(key).inserted else { continue }
            tags.append(AITagRef(category: category, value: value))
        }
        return tags
    }

    static func parseKeywords(_ text: String) -> [String] {
        guard let object = parseJSON(text) as? [String: Any] else { return [] }
        let items = object["keywords"] as? [Any] ?? []
        var keywords: [String] = []
        var seen = Set<String>()
        for item in items {
            let raw: String
            if let text = item as? String {
                raw = text
            } else if let object = item as? [String: Any] {
                raw = stringValue(object["value"]).isEmpty ? stringValue(object["keyword"]) : stringValue(object["value"])
            } else {
                continue
            }
            guard let formatted = StockKeywordExpander.gettyKeyword(raw), seen.insert(formatted).inserted else {
                continue
            }
            keywords.append(formatted)
            if keywords.count >= 20 { break }
        }
        return keywords
    }

    static func pickFrames<T>(_ frames: [T], limit: Int) -> [T] {
        if limit <= 0 || frames.count <= limit {
            return frames
        }
        if limit == 1 {
            return [frames[frames.count / 2]]
        }
        let step = Double(frames.count - 1) / Double(limit - 1)
        return (0..<limit).map { index in
            frames[pythonRound(Double(index) * step)]
        }
    }

    static func geminiPayload(prompt: String, frames: [String]) -> [String: Any] {
        var parts: [[String: Any]] = [["text": prompt]]
        for frame in frames {
            parts.append([
                "inlineData": [
                    "mimeType": "image/jpeg",
                    "data": frame,
                ] as [String: Any],
            ])
        }
        return [
            "contents": [["parts": parts]],
            "generationConfig": [
                "responseMimeType": "application/json",
            ],
        ]
    }

    static func openaiPayload(prompt: String, model: String, frames: [String]) -> [String: Any] {
        var content: [[String: Any]] = [["type": "text", "text": prompt]]
        for frame in frames {
            content.append([
                "type": "image_url",
                "image_url": [
                    "url": "data:image/jpeg;base64,\(frame)",
                    "detail": "low",
                ] as [String: Any],
            ])
        }
        return [
            "model": model,
            "temperature": 0.2,
            "response_format": ["type": "json_object"],
            "messages": [["role": "user", "content": content]],
        ]
    }

    static func shouldRetry(status: Int, body: String) -> Bool {
        if retryableStatus.contains(status) { return true }
        let upper = body.uppercased()
        return upper.contains("RESOURCE_EXHAUSTED") || upper.contains("UNAVAILABLE")
    }

    static func retrySeconds(status _: Int, body: String, attempt: Int) -> TimeInterval {
        let delay = parsedRetryDelay(body) ?? (1.0 + Double(attempt))
        return min(max(delay, 0.4), 2.0)
    }

    static func parsedRetryDelay(_ body: String) -> Double? {
        guard let object = decodeObject(body), let error = object["error"] as? [String: Any] else {
            return nil
        }
        for item in error["details"] as? [[String: Any]] ?? [] {
            if let raw = item["retryDelay"] as? String, raw.hasSuffix("s") {
                if let value = Double(raw.dropLast()) { return value }
            } else if let value = item["retryDelay"] as? Double {
                return value
            } else if let value = item["retryDelay"] as? Int {
                return Double(value)
            }
        }
        return nil
    }

    static func httpErrorMessage(status: Int, body: String) -> String {
        if let object = decodeObject(body) {
            if let error = object["error"] as? [String: Any], let message = error["message"] as? String, !message.isEmpty {
                return String(message.prefix(300))
            }
            if let message = object["message"] as? String, !message.isEmpty {
                return String(message.prefix(300))
            }
        }
        return "http_\(status)"
    }

    static func geminiError(_ data: [String: Any]) -> String {
        if let error = data["error"] as? [String: Any], let message = error["message"] as? String, !message.isEmpty {
            return String(message.prefix(200))
        }
        return "empty_gemini_response"
    }

    static func geminiText(from data: [String: Any]) throws -> String {
        if let blocked = (data["promptFeedback"] as? [String: Any])?["blockReason"] as? String, !blocked.isEmpty {
            throw AITagError.requestFailed("gemini_blocked:\(blocked)")
        }
        let candidates = data["candidates"] as? [[String: Any]] ?? []
        guard let first = candidates.first else {
            throw AITagError.requestFailed(geminiError(data))
        }
        let parts = (first["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
        let texts = parts.compactMap { $0["text"] as? String }.filter { !$0.isEmpty }
        guard let text = texts.first else {
            throw AITagError.requestFailed("empty_gemini_response")
        }
        return text
    }

    static func openaiText(from data: [String: Any]) throws -> String {
        let choices = data["choices"] as? [[String: Any]] ?? []
        guard let first = choices.first else {
            throw AITagError.requestFailed("empty_openai_response")
        }
        return ((first["message"] as? [String: Any])?["content"] as? String) ?? ""
    }

    /// Python 3 `round()` for non-negative values (half to even).
    static func pythonRound(_ value: Double) -> Int {
        let floor = Darwin.floor(value)
        let fraction = value - floor
        if fraction < 0.5 { return Int(floor) }
        if fraction > 0.5 { return Int(floor) + 1 }
        let even = Int(floor)
        return even.isMultiple(of: 2) ? even : even + 1
    }

    private static func normalizeExamples(_ examples: [[String: Any]]?) -> [[String: Any]] {
        guard let examples else { return [] }
        var cleaned: [[String: Any]] = []
        for item in examples.prefix(8) {
            let ai = exampleTags(item["ai"])
            let kept = exampleTags(item["kept"])
            guard !ai.isEmpty, !kept.isEmpty else { continue }
            cleaned.append([
                "ai": ai.map { ["category": $0.category, "value": $0.value] },
                "kept": kept.map { ["category": $0.category, "value": $0.value] },
            ])
        }
        return cleaned
    }

    private static func exampleTags(_ items: Any?) -> [AITagRef] {
        guard let items = items as? [Any] else { return [] }
        var tags: [AITagRef] = []
        var seen = Set<String>()
        for item in items {
            guard let object = item as? [String: Any] else { continue }
            let category = stringValue(object["category"])
            let value = stringValue(object["value"])
            guard !category.isEmpty, !value.isEmpty else { continue }
            let key = "\(category)/\(value)"
            guard seen.insert(key).inserted else { continue }
            tags.append(AITagRef(category: category, value: value))
            if tags.count >= 12 { break }
        }
        return tags
    }

    private static func parseJSON(_ text: String) -> Any? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var cleaned = trimmed
        if cleaned.hasPrefix("```") {
            cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "`"))
            if cleaned.lowercased().hasPrefix("json") {
                cleaned = String(cleaned.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if let parsed = decodeJSON(cleaned) {
            return parsed
        }
        guard let start = cleaned.firstIndex(of: "{"), let end = cleaned.lastIndex(of: "}"), start < end else {
            return nil
        }
        return decodeJSON(String(cleaned[start...end]))
    }

    private static func decodeJSON(_ text: String) -> Any? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private static func decodeObject(_ text: String) -> [String: Any]? {
        decodeJSON(text) as? [String: Any]
    }

    private static func stringValue(_ value: Any?) -> String {
        guard let text = value as? String else { return "" }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum CompactJSON {
    static func stringify(_ value: Any) -> String {
        encode(value)
    }

    private static func encode(_ value: Any) -> String {
        if value is NSNull {
            return "null"
        }
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
            return number.boolValue ? "true" : "false"
        }
        switch value {
        case let string as String:
            return quote(string)
        case let bool as Bool:
            return bool ? "true" : "false"
        case let int as Int:
            return String(int)
        case let int as Int64:
            return String(int)
        case let uint as UInt:
            return String(uint)
        case let double as Double:
            return formatDouble(double)
        case let float as Float:
            return formatDouble(Double(float))
        case let number as NSNumber:
            if CFNumberIsFloatType(number) {
                return formatDouble(number.doubleValue)
            }
            return String(number.int64Value)
        case let array as [[String: String]]:
            return "[" + array.map { encode($0) }.joined(separator: ", ") + "]"
        case let array as [[String: Any]]:
            return "[" + array.map { encode($0) }.joined(separator: ", ") + "]"
        case let array as [Any]:
            return "[" + array.map(encode).joined(separator: ", ") + "]"
        case let dict as [String: String]:
            let parts = dict.map { key, nested in
                "\(quote(key)): \(encode(nested))"
            }
            return "{" + parts.joined(separator: ", ") + "}"
        case let dict as [String: Any]:
            let parts = dict.map { key, nested in
                "\(quote(key)): \(encode(nested))"
            }
            return "{" + parts.joined(separator: ", ") + "}"
        default:
            return "null"
        }
    }

    private static func formatDouble(_ value: Double) -> String {
        if value.isNaN || value.isInfinite {
            return "null"
        }
        if value.rounded() == value, abs(value) <= Double(Int64.max) {
            return String(Int64(value))
        }
        return String(value)
    }

    private static func quote(_ string: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: string, options: [.fragmentsAllowed])
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }
}
