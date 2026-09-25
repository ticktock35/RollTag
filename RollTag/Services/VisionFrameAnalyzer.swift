import CoreGraphics
import Foundation
import ImageIO
import Vision

struct VisionObservation: Equatable, Sendable {
    var people: String
    var peopleCount: Int
    var hasHands: Bool
    var face: String
    var scenes: [String]
    var animals: [String]
    var text: [String]
    var isReliable: Bool

    static let none = VisionObservation(
        people: "none",
        peopleCount: 0,
        hasHands: false,
        face: "none",
        scenes: [],
        animals: [],
        text: [],
        isReliable: true
    )

    static let unreliable = VisionObservation(
        people: "none",
        peopleCount: 0,
        hasHands: false,
        face: "none",
        scenes: [],
        animals: [],
        text: [],
        isReliable: false
    )

    var contextPayload: [String: Any] {
        var payload: [String: Any] = [
            "people": people,
            "people_count": peopleCount,
            "hands": hasHands,
            "face": face,
        ]
        if !scenes.isEmpty { payload["scenes"] = scenes }
        if !animals.isEmpty { payload["animals"] = animals }
        if !text.isEmpty { payload["text"] = text }
        return payload
    }
}

enum VisionFrameAnalyzer {
    static let maxFrames = 2
    static let maxEdge = 512

    private struct FrameFacts: Sendable {
        var peopleCount: Int
        var faceCount: Int
        var hasHands: Bool
        var maxFaceArea: Double
        var scenes: [String]
        var animals: [String]
        var text: [String]
    }

    static func observe(frames: [Data]) async -> VisionObservation {
        let picked = pickFrames(frames)
        guard !picked.isEmpty else { return .none }
        return await withTaskGroup(of: FrameFacts?.self) { group in
            for (index, data) in picked.enumerated() {
                group.addTask {
                    analyzeFrame(data, extras: index == 0)
                }
            }
            var facts: [FrameFacts] = []
            for await fact in group {
                if let fact { facts.append(fact) }
            }
            guard !facts.isEmpty else { return .none }
            return merge(facts)
        }
    }

    static func pickFrames<T>(_ frames: [T], limit: Int = maxFrames) -> [T] {
        guard limit > 0, !frames.isEmpty else { return [] }
        if frames.count <= limit { return frames }
        if limit == 1 { return [frames[frames.count / 2]] }
        return [frames[0], frames[frames.count - 1]]
    }

    static func peopleID(count: Int) -> String {
        switch count {
        case ...0: return "none"
        case 1: return "one"
        case 2: return "two"
        case 3...10: return "group"
        default: return "crowd"
        }
    }

    static func faceID(maxFaceArea: Double, peopleCount: Int) -> String {
        guard peopleCount > 0 else { return "none" }
        if maxFaceArea >= 0.12 { return "portrait" }
        if maxFaceArea > 0, maxFaceArea < 0.03 { return "distant" }
        if maxFaceArea >= 0.03 { return "visible" }
        return "distant"
    }

    static func resolved(_ vision: VisionObservation?) -> VisionObservation {
        guard let vision, vision.isReliable else { return .none }
        return vision
    }

    static func resolvedPeopleCount(bodies: Int, faces: Int, animals: [String], hasHands: Bool) -> Int {
        if !animals.isEmpty, faces == 0 {
            return 0
        }
        if hasHands, bodies <= 0 {
            return 1
        }
        return max(0, bodies)
    }

    static func applyGate(_ tags: [TagAssignment], vision: VisionObservation?) -> [TagAssignment] {
        guard vision != nil else {
            return tags.filter { tag in
                !(tag.isCustom && isCalendarKeyword(tag.value))
            }
        }
        let vision = resolved(vision)
        var result: [TagAssignment] = []
        var seen = Set<String>()

        func append(_ tag: TagAssignment) {
            guard seen.insert(tag.identityKey).inserted else { return }
            result.append(tag)
        }

        for tag in tags {
            if tag.category == "people" {
                if countIDs.contains(tag.value) { continue }
                if vision.people == "none", needsPerson.contains(tag.value) { continue }
                if tag.value == "portrait", vision.face != "portrait" { continue }
                if tag.value == "distant", vision.face != "distant" { continue }
                if tag.value == "hands", !vision.hasHands || vision.people == "none" { continue }
            }
            if tag.category == "animals", tag.value == "pet", vision.animals.isEmpty {
                continue
            }
            if vision.people == "none", needsLivingPerson.contains(tag.identityKey) {
                continue
            }
            if tag.isCustom, shouldDropKeyword(tag.value, vision: vision) {
                continue
            }
            append(tag)
        }
        append(.ai(category: "people", value: vision.people))
        if vision.hasHands, vision.people != "none" {
            append(.ai(category: "people", value: "hands"))
        }
        return result
    }

    static func isPeopleKeyword(_ raw: String) -> Bool {
        let formatted = normalizedKeyword(raw)
        if formatted == "no people" { return false }
        let words = formatted.split(whereSeparator: \.isWhitespace).map(String.init)
        return words.contains { peopleWords.contains($0) }
    }

    static func isCalendarKeyword(_ raw: String) -> Bool {
        calendarWords.contains(normalizedKeyword(raw))
    }

    static func isPetKeyword(_ raw: String) -> Bool {
        let formatted = normalizedKeyword(raw)
        if petPhrases.contains(formatted) { return true }
        let words = formatted.split(whereSeparator: \.isWhitespace).map(String.init)
        return words.contains { petWords.contains($0) }
    }

    private static func shouldDropKeyword(_ raw: String, vision: VisionObservation) -> Bool {
        if isCalendarKeyword(raw) { return true }
        if vision.people == "none", isPeopleKeyword(raw) { return true }
        if vision.animals.isEmpty, isPetKeyword(raw) { return true }
        return false
    }

    private static func normalizedKeyword(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static let countIDs: Set<String> = ["none", "one", "two", "group", "crowd"]
    private static let needsPerson: Set<String> = [
        "portrait", "distant", "silhouette", "hands",
        "infant", "child", "teen", "youngAdult", "adult", "senior",
    ]
    private static let needsLivingPerson: Set<String> = [
        "lifestyle/family", "lifestyle/friends", "sport/spectators", "sport/kidsPlay",
    ]
    private static let peopleWords: Set<String> = [
        "people", "person", "man", "woman", "men", "women",
        "crowd", "portrait", "human", "humans", "child", "children",
        "boy", "girl", "baby", "infant", "teen", "adult", "senior",
        "couple", "someone",
    ]
    private static let calendarWords: Set<String> = [
        "january", "february", "march", "april", "may", "june",
        "july", "august", "september", "october", "november", "december",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
    ]
    private static let petPhrases: Set<String> = ["pet", "pets", "house pet"]
    private static let petWords: Set<String> = ["pet", "pets", "puppy", "kitten"]

    private static func merge(_ facts: [FrameFacts]) -> VisionObservation {
        let animals = uniqued(facts.flatMap(\.animals), limit: 4)
        let faces = facts.map(\.faceCount).max() ?? 0
        let bodies = facts.map(\.peopleCount).max() ?? 0
        var hasHands = facts.contains(where: \.hasHands)
        if !animals.isEmpty, faces == 0 {
            hasHands = false
        }
        let peopleCount = resolvedPeopleCount(
            bodies: bodies,
            faces: faces,
            animals: animals,
            hasHands: hasHands
        )
        return VisionObservation(
            people: peopleID(count: peopleCount),
            peopleCount: peopleCount,
            hasHands: hasHands && peopleCount > 0,
            face: faceID(maxFaceArea: facts.map(\.maxFaceArea).max() ?? 0, peopleCount: peopleCount),
            scenes: uniqued(facts.flatMap(\.scenes), limit: 5),
            animals: animals,
            text: uniqued(facts.flatMap(\.text), limit: 6),
            isReliable: true
        )
    }

    private static func analyzeFrame(_ data: Data, extras: Bool) -> FrameFacts? {
        guard let image = cgImage(from: data) else { return nil }
        let faces = VNDetectFaceRectanglesRequest()
        let bodies = VNDetectHumanRectanglesRequest()
        let hands = VNDetectHumanHandPoseRequest()
        hands.maximumHandCount = 2
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([faces, bodies, hands])
        } catch {
            return nil
        }
        var scenes: [String] = []
        var animals: [String] = []
        var text: [String] = []
        let animalRequest = VNRecognizeAnimalsRequest()
        if extras {
            let sceneRequest = VNClassifyImageRequest()
            let textRequest = VNRecognizeTextRequest()
            textRequest.recognitionLevel = .fast
            textRequest.usesLanguageCorrection = false
            textRequest.minimumTextHeight = 0.04
            try? handler.perform([animalRequest, sceneRequest, textRequest])
            scenes = sceneLabels(sceneRequest.results)
            animals = animalLabels(animalRequest.results)
            text = textLabels(textRequest.results)
        } else {
            try? handler.perform([animalRequest])
            animals = animalLabels(animalRequest.results)
        }
        let faceBoxes = faces.results ?? []
        let bodyBoxes = (bodies.results ?? []).filter { $0.confidence >= 0.7 }
        let maxFaceArea = faceBoxes.map { $0.boundingBox.width * $0.boundingBox.height }.max() ?? 0
        return FrameFacts(
            peopleCount: bodyBoxes.count,
            faceCount: faceBoxes.count,
            hasHands: (hands.results ?? []).contains { $0.confidence >= 0.4 },
            maxFaceArea: maxFaceArea,
            scenes: scenes,
            animals: animals,
            text: text
        )
    }

    private static func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxEdge,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func sceneLabels(_ results: [VNClassificationObservation]?) -> [String] {
        let skip: Set<String> = ["photograph", "photography", "image", "art", "screenshot"]
        let labels = (results ?? [])
            .filter { $0.confidence >= 0.4 }
            .compactMap { observation -> String? in
                let label = observation.identifier
                    .replacingOccurrences(of: "_", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                guard !label.isEmpty, !skip.contains(label) else { return nil }
                return label
            }
        return Array(labels.prefix(5))
    }

    private static func animalLabels(_ results: [VNRecognizedObjectObservation]?) -> [String] {
        (results ?? []).compactMap { observation in
            guard let label = observation.labels.first, label.confidence >= 0.4 else { return nil }
            return label.identifier.replacingOccurrences(of: "_", with: " ").lowercased()
        }
    }

    private static func textLabels(_ results: [VNRecognizedTextObservation]?) -> [String] {
        (results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first, candidate.confidence >= 0.65 else {
                return nil
            }
            let collapsed = candidate.string
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let words = collapsed.split(whereSeparator: \.isWhitespace)
            guard (2...24).contains(collapsed.count), (1...4).contains(words.count) else { return nil }
            return collapsed
        }
    }

    private static func uniqued(_ items: [String], limit: Int) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for item in items {
            let key = item.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(item)
            if result.count == limit { break }
        }
        return result
    }
}
