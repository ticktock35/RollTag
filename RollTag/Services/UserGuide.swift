import Foundation

struct HelpTopic: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var body: String

    var blocks: [HelpBlock] {
        UserGuide.blocks(in: body)
    }
}

enum HelpBlock: Equatable, Sendable {
    case paragraph(String)
    case bullets([String])
    case steps([String])
}

enum UserGuide {
    static let expectedIDs = [
        "start", "warehouse", "photos", "videos", "duplicates", "shortcuts", "search", "ai", "batch", "gpx",
    ]

    static func topics(localeID: String) -> [HelpTopic] {
        parse(loadMarkdown(localeID: localeID))
    }

    static func loadMarkdown(localeID: String) -> String {
        let bundle = Bundle(for: AppModel.self)
        let name = localeID.hasPrefix("zh") ? "UserGuide.zh-Hant" : "UserGuide.en"
        if let url = bundle.url(forResource: name, withExtension: "md"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            return text
        }
        if let url = bundle.url(forResource: "UserGuide.en", withExtension: "md"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            return text
        }
        return ""
    }

    static func parse(_ markdown: String) -> [HelpTopic] {
        var topics: [HelpTopic] = []
        var title = ""
        var id = ""
        var lines: [String] = []

        func flush() {
            guard !title.isEmpty, !id.isEmpty else { return }
            let body = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            topics.append(HelpTopic(id: id, title: title, body: body))
            title = ""
            id = ""
            lines = []
        }

        for raw in markdown.components(separatedBy: "\n") {
            if raw.hasPrefix("## ") {
                flush()
                let heading = String(raw.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                if let parsed = headingID(heading) {
                    title = parsed.title
                    id = parsed.id
                }
            } else if raw.hasPrefix("# ") {
                continue
            } else if !title.isEmpty {
                lines.append(raw)
            }
        }
        flush()
        return topics
    }

    private static func headingID(_ heading: String) -> (title: String, id: String)? {
        guard let open = heading.range(of: "{#"),
              let close = heading.range(of: "}", range: open.upperBound..<heading.endIndex)
        else { return nil }
        let id = String(heading[open.upperBound..<close.lowerBound])
            .trimmingCharacters(in: .whitespaces)
        let title = heading[..<open.lowerBound].trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, !title.isEmpty else { return nil }
        return (title, id)
    }

    static func blocks(in body: String) -> [HelpBlock] {
        var result: [HelpBlock] = []
        var paragraph: [String] = []
        var bullets: [String] = []
        var steps: [String] = []

        func flushParagraph() {
            let text = paragraph.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                result.append(.paragraph(text))
            }
            paragraph = []
        }

        func flushBullets() {
            if !bullets.isEmpty {
                result.append(.bullets(bullets))
            }
            bullets = []
        }

        func flushSteps() {
            if !steps.isEmpty {
                result.append(.steps(steps))
            }
            steps = []
        }

        func flushAll() {
            flushParagraph()
            flushBullets()
            flushSteps()
        }

        for raw in body.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flushAll()
                continue
            }
            if let item = bulletItem(line) {
                flushParagraph()
                flushSteps()
                bullets.append(item)
                continue
            }
            if let item = stepItem(line) {
                flushParagraph()
                flushBullets()
                steps.append(item)
                continue
            }
            flushBullets()
            flushSteps()
            paragraph.append(line)
        }
        flushAll()
        return result
    }

    static func inlineMarkdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let parsed = try? AttributedString(markdown: text, options: options) {
            return parsed
        }
        return AttributedString(text)
    }

    private static func bulletItem(_ line: String) -> String? {
        if line.hasPrefix("- ") { return String(line.dropFirst(2)) }
        if line.hasPrefix("* ") { return String(line.dropFirst(2)) }
        return nil
    }

    private static func stepItem(_ line: String) -> String? {
        guard let dot = line.firstIndex(of: "."),
              dot > line.startIndex,
              line[line.startIndex..<dot].allSatisfy(\.isNumber)
        else { return nil }
        let after = line[line.index(after: dot)...]
        guard after.first == " " else { return nil }
        return after.dropFirst().trimmingCharacters(in: .whitespaces)
    }
}
