import Foundation

struct FolderTimeOffset: Equatable, Hashable, Sendable {
    var years: Int = 0
    var days: Int = 0
    var hours: Int = 0
    var minutes: Int = 0
    var seconds: Int = 0

    static let zero = FolderTimeOffset()

    var isZero: Bool {
        years == 0 && days == 0 && hours == 0 && minutes == 0 && seconds == 0
    }

    func applied(to date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(
            byAdding: DateComponents(
                year: years,
                day: days,
                hour: hours,
                minute: minutes,
                second: seconds
            ),
            to: date
        ) ?? date
    }

    func summary() -> String {
        if isZero { return String(localized: "offset.zero") }
        var parts: [String] = []
        appendPart(years, unit: "offset.year", into: &parts)
        appendPart(days, unit: "offset.day", into: &parts)
        appendPart(hours, unit: "offset.hour", into: &parts)
        appendPart(minutes, unit: "offset.minute", into: &parts)
        appendPart(seconds, unit: "offset.second", into: &parts)
        return parts.joined(separator: " ")
    }

    private func appendPart(_ value: Int, unit: String, into parts: inout [String]) {
        guard value != 0 else { return }
        let label = String(localized: String.LocalizationValue(unit))
        parts.append(value > 0 ? "+\(value) \(label)" : "\(value) \(label)")
    }

    static func parse(_ value: Any) -> FolderTimeOffset? {
        if let number = value as? Int {
            return FolderTimeOffset(minutes: number)
        }
        if let number = value as? NSNumber {
            return FolderTimeOffset(minutes: number.intValue)
        }
        guard let object = value as? [String: Any] else { return nil }
        return FolderTimeOffset(
            years: intValue(object["years"]),
            days: intValue(object["days"]),
            hours: intValue(object["hours"]),
            minutes: intValue(object["minutes"]),
            seconds: intValue(object["seconds"])
        )
    }

    func jsonObject() -> [String: Int] {
        var object: [String: Int] = [:]
        if years != 0 { object["years"] = years }
        if days != 0 { object["days"] = days }
        if hours != 0 { object["hours"] = hours }
        if minutes != 0 { object["minutes"] = minutes }
        if seconds != 0 { object["seconds"] = seconds }
        return object
    }

    private static func intValue(_ raw: Any?) -> Int {
        if let number = raw as? Int { return number }
        if let number = raw as? NSNumber { return number.intValue }
        return 0
    }
}

struct FolderTimeOffsetPrompt: Identifiable, Equatable {
    var warehouseID: UUID
    var folder: String
    var folderTitle: String
    var offset: FolderTimeOffset

    var id: String { "\(warehouseID.uuidString)/\(folder)" }
}
