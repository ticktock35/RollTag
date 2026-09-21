import Foundation

enum AITagSuggester {
    static func catalogPayload(catalog: TagCatalog, locale: String, customValues: [String]) -> [String: Any] {
        var categories: [[String: Any]] = catalog.categories.map { category in
            [
                "id": category.id,
                "name": category.localizedName(locale: locale),
                "tags": category.tags.map { tag in
                    [
                        "id": tag.id,
                        "name": tag.localizedName(locale: locale),
                        "en": tag.localizedName(locale: "en"),
                    ]
                },
            ]
        }
        let customs = customValues
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !customs.isEmpty {
            categories.append([
                "id": TagAssignment.customCategory,
                "name": "custom",
                "tags": customs.map { ["id": $0, "name": $0] },
            ])
        }
        return ["categories": categories]
    }

    static func contextPayload(
        footage: Footage,
        warehouseName: String,
        live: MediaMetadataSnapshot = MediaMetadataSnapshot()
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "filename": footage.filename,
            "relative_path": footage.relativePath,
            "warehouse_name": warehouseName,
            "file_size_bytes": footage.size,
        ]
        if !footage.directoryPath.isEmpty {
            payload["directory"] = footage.directoryPath
        }
        if let duration = footage.duration, duration.isFinite, duration > 0 {
            payload["duration_seconds"] = duration
        }
        let capture = merge(stored: footage.captureMetadata, live: live)
        if let capturedAt = capture.capturedAtForAI() {
            payload["captured_at"] = capturedAt
        }
        if let latitude = capture.latitude, let longitude = capture.longitude {
            var gps: [String: Any] = [
                "latitude": latitude,
                "longitude": longitude,
            ]
            if let altitude = capture.altitude {
                gps["altitude"] = altitude
            }
            payload["gps"] = gps
        }
        return payload
    }

    private static func merge(stored: MediaMetadataSnapshot, live: MediaMetadataSnapshot) -> MediaMetadataSnapshot {
        var next = stored
        if next.capturedAt == nil && next.capturedAtLocal == nil {
            next.capturedAt = live.capturedAt
            next.capturedAtLocal = live.capturedAtLocal
            next.capturedAtHasTimeZone = live.capturedAtHasTimeZone
            next.capturedAtSource = live.capturedAtSource
        }
        if !next.hasGPS {
            next.latitude = live.latitude
            next.longitude = live.longitude
            next.altitude = live.altitude
        }
        return next
    }

    static func assignments(
        from raw: [[String: String]],
        catalog: TagCatalog,
        customValues: Set<String>,
        keywords: [String] = []
    ) -> [TagAssignment] {
        var seen = Set<String>()
        var result: [TagAssignment] = []
        for item in raw {
            let category = item["category"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let value = item["value"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard isAllowed(category: category, value: value, catalog: catalog, customValues: customValues) else {
                continue
            }
            let key = "\(category)/\(value)"
            guard seen.insert(key).inserted else { continue }
            result.append(.ai(category: category, value: value))
        }
        for keyword in keywords {
            guard let formatted = StockKeywordExpander.gettyKeyword(keyword) else { continue }
            let key = "\(TagAssignment.customCategory)/\(formatted)"
            guard seen.insert(key).inserted else { continue }
            result.append(.ai(category: TagAssignment.customCategory, value: formatted))
        }
        return result
    }

    static func assignments(
        from payload: [String: Any],
        catalog: TagCatalog,
        customValues: Set<String>
    ) -> [TagAssignment] {
        assignments(
            from: suggestedTags(in: payload),
            catalog: catalog,
            customValues: customValues,
            keywords: suggestedKeywords(in: payload)
        )
    }

    static func suggestedTags(in payload: [String: Any]) -> [[String: String]] {
        let items = payload["tags"] as? [[String: Any]] ?? []
        return items.compactMap { item in
            guard let category = stringValue(item["category"]), let value = stringValue(item["value"]) else {
                return nil
            }
            return ["category": category, "value": value]
        }
    }

    static func suggestedKeywords(in payload: [String: Any]) -> [String] {
        let items = payload["keywords"] as? [Any] ?? []
        return items.compactMap { item in
            if let text = stringValue(item) { return text }
            if let object = item as? [String: Any] {
                return stringValue(object["value"]) ?? stringValue(object["keyword"])
            }
            return nil
        }
    }

    private static func isAllowed(
        category: String,
        value: String,
        catalog: TagCatalog,
        customValues: Set<String>
    ) -> Bool {
        if category == TagAssignment.customCategory {
            if customValues.contains(value) { return true }
            return StockKeywordExpander.isVisibleCustomLabel(value)
        }
        return catalog.categories.contains { group in
            group.id == category && group.tags.contains { $0.id == value }
        }
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let text as String:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        default:
            return nil
        }
    }
}
