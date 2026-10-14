import AppKit
import CoreGraphics
import Foundation
import ImageIO
import Vision

final class LocalAIEngine: @unchecked Sendable {
    static let shared = LocalAIEngine()

    private let lock = NSLock()

    private init() {}

    func suggest(scheme: LocalAIScheme, frames: [Data], catalog: TagCatalog) async throws -> [String: Any] {
        guard !frames.isEmpty else { throw AITagError.missingFrames }
        switch scheme {
        case .appleVision:
            return await suggestAppleVision(frames: frames, catalog: catalog)
        case .florence2Base:
            return try await suggestFlorence2Base(frames: frames, catalog: catalog)
        case .ramPlus:
            return try await suggestRAMPlus(frames: frames, catalog: catalog)
        }
    }

    // MARK: - Visual Analysis Pipeline

    private struct VisualAnalysis {
        var mergedClassifications: [String: Float]
        var maxBodies: Int
        var maxFaces: Int
        var maxFaceArea: Double
        var maxBodyArea: Double
        var hasHands: Bool
        var hasSmile: Bool
        var detectedAnimals: Set<String>
        var detectedText: [String]
        var tone: (isBW: Bool, isVivid: Bool, isWarm: Bool, isCool: Bool, isDark: Bool)
    }

    private func analyzeFrames(_ frames: [Data]) -> VisualAnalysis? {
        let sampledFrames = pickSampleFrames(frames, maxCount: 4)
        var cgImages: [CGImage] = []
        for data in sampledFrames {
            if let cg = cgImage(from: data) {
                cgImages.append(cg)
            }
        }
        guard !cgImages.isEmpty else { return nil }

        var mergedClassifications: [String: Float] = [:]
        var maxBodies = 0
        var maxFaces = 0
        var maxFaceArea: Double = 0
        var maxBodyArea: Double = 0
        var hasHands = false
        var hasSmile = false
        var detectedAnimals: Set<String> = []
        var detectedText: [String] = []

        for cg in cgImages {
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            let reqClass = VNClassifyImageRequest()
            let reqAnim = VNRecognizeAnimalsRequest()
            let reqFaces = VNDetectFaceLandmarksRequest()
            let reqBodies = VNDetectHumanRectanglesRequest()
            let reqHands = VNDetectHumanHandPoseRequest()
            reqHands.maximumHandCount = 2
            let reqText = VNRecognizeTextRequest()
            reqText.recognitionLevel = .fast
            reqText.usesLanguageCorrection = false
            reqText.minimumTextHeight = 0.04

            try? handler.perform([reqClass, reqAnim, reqFaces, reqBodies, reqHands, reqText])

            let bodies = reqBodies.results ?? []
            let bodyCount = bodies.filter { $0.confidence >= 0.50 }.count
            maxBodies = max(maxBodies, bodyCount)
            let bodyArea = bodies.map { Double($0.boundingBox.width * $0.boundingBox.height) }.max() ?? 0
            maxBodyArea = max(maxBodyArea, bodyArea)

            let faces = reqFaces.results ?? []
            maxFaces = max(maxFaces, faces.count)
            let faceArea = faces.map { Double($0.boundingBox.width * $0.boundingBox.height) }.max() ?? 0
            maxFaceArea = max(maxFaceArea, faceArea)

            for face in faces {
                if let lips = face.landmarks?.outerLips, lips.pointCount >= 6 {
                    let pts = lips.normalizedPoints
                    if let minY = pts.map(\.y).min(), let maxY = pts.map(\.y).max(),
                       let minX = pts.map(\.x).min(), let maxX = pts.map(\.x).max() {
                        let h = maxY - minY
                        let w = maxX - minX
                        if w > 0 && (h / w) >= 0.25 {
                            hasSmile = true
                        }
                    }
                }
            }

            if (reqHands.results ?? []).contains(where: { $0.confidence >= 0.35 }) {
                hasHands = true
            }

            for anim in reqAnim.results ?? [] {
                if let label = anim.labels.first, label.confidence >= 0.25 {
                    detectedAnimals.insert(label.identifier.lowercased())
                }
            }

            for c in reqClass.results ?? [] where c.confidence >= 0.005 {
                let id = c.identifier.lowercased()
                mergedClassifications[id] = max(mergedClassifications[id] ?? 0, c.confidence)
                if animalIdentifiers.contains(id) {
                    detectedAnimals.insert(id)
                }
                if ["smile", "happy", "laugh", "cheerful", "grinning"].contains(id) && c.confidence >= 0.015 {
                    hasSmile = true
                }
            }

            for t in reqText.results ?? [] {
                if let candidate = t.topCandidates(1).first, candidate.confidence >= 0.65 {
                    let cleaned = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    if (2...30).contains(cleaned.count) {
                        detectedText.append(cleaned)
                    }
                }
            }
        }

        let tone = analyzeTone(cg: cgImages[0])

        return VisualAnalysis(
            mergedClassifications: mergedClassifications,
            maxBodies: maxBodies,
            maxFaces: maxFaces,
            maxFaceArea: maxFaceArea,
            maxBodyArea: maxBodyArea,
            hasHands: hasHands,
            hasSmile: hasSmile,
            detectedAnimals: detectedAnimals,
            detectedText: detectedText,
            tone: tone
        )
    }

    // MARK: - Tag & Keyword Builders

    private func appendTag(
        category: String,
        value: String,
        catalog: TagCatalog,
        suggestedTags: inout [[String: String]],
        seenTags: inout Set<String>
    ) {
        guard catalog.categories.contains(where: { $0.id == category && $0.tags.contains(where: { $0.id == value }) }) else {
            return
        }
        let key = "\(category)/\(value)"
        guard seenTags.insert(key).inserted else { return }
        suggestedTags.append(["category": category, "value": value])
    }

    private func appendKeyword(
        _ raw: String,
        keywords: inout [String],
        seenKeywords: inout Set<String>
    ) {
        guard let formatted = StockKeywordExpander.gettyKeyword(raw) else { return }
        guard seenKeywords.insert(formatted).inserted else { return }
        keywords.append(formatted)
    }

    // MARK: - Apple Vision Tagger

    private func suggestAppleVision(frames: [Data], catalog: TagCatalog) async -> [String: Any] {
        guard let analysis = analyzeFrames(frames) else {
            return [
                "tags": [["category": "people", "value": "none"]],
                "keywords": ["no people"],
                "provider": AIProvider.appleVision.rawValue,
                "model": LocalAIScheme.appleVision.rawValue,
            ]
        }

        var suggestedTags: [[String: String]] = []
        var seenTags = Set<String>()
        var keywords: [String] = []
        var seenKeywords = Set<String>()

        func addTag(_ cat: String, _ val: String) {
            appendTag(category: cat, value: val, catalog: catalog, suggestedTags: &suggestedTags, seenTags: &seenTags)
        }
        func addKeyword(_ raw: String) {
            appendKeyword(raw, keywords: &keywords, seenKeywords: &seenKeywords)
        }

        // 1. People count & framing
        let resolvedCount = resolvePeopleCount(analysis: analysis)
        let peopleID: String
        switch resolvedCount {
        case ...0: peopleID = "none"
        case 1: peopleID = "one"
        case 2: peopleID = "two"
        case 3...10: peopleID = "group"
        default: peopleID = "crowd"
        }
        addTag("people", peopleID)

        if resolvedCount == 0 {
            addKeyword("no people")
            addTag("shot", "wide")
            addKeyword("wide shot")
        } else {
            if resolvedCount == 1 { addKeyword("one person") }
            else if resolvedCount == 2 { addKeyword("two people") }
            else if resolvedCount <= 10 { addKeyword("group of people") }
            else { addKeyword("crowd of people") }

            // Framing based on face & body area
            if analysis.maxFaceArea >= 0.08 {
                addTag("people", "portrait")
                addTag("shot", "closeUp")
                addTag("shot", "headshot")
                addKeyword("portrait")
                addKeyword("close up")
                addKeyword("headshot")
            } else if analysis.maxFaceArea >= 0.015 || (resolvedCount == 1 && analysis.maxBodyArea >= 0.15) {
                addTag("people", "portrait")
                addTag("shot", "waistUp")
                addTag("shot", "medium")
                addKeyword("portrait")
                addKeyword("waist up")
                addKeyword("medium shot")
            } else if analysis.maxFaceArea > 0 && analysis.maxFaceArea < 0.008 && analysis.maxBodyArea < 0.08 {
                addTag("people", "distant")
                addTag("shot", "wide")
                addKeyword("distant")
                addKeyword("wide shot")
            } else {
                addTag("shot", "medium")
                addKeyword("medium shot")
            }

            if analysis.hasHands {
                addTag("people", "hands")
            }

            if let demo = resolveDemographicTag(analysis: analysis) {
                addTag("people", demo.tag)
                addKeyword(demo.keyword)
            }
        }

        // 2. Animals
        for anim in analysis.detectedAnimals {
            addKeyword(anim.replacingOccurrences(of: "_", with: " "))
            if ["dog", "cat", "husky", "puppy", "kitten", "pet", "canine", "feline"].contains(anim) {
                addTag("animals", "pet")
            } else if ["bird", "owl", "raptor", "raven", "eagle", "hawk", "duck", "waterfowl", "sparrow", "pigeon"].contains(anim) {
                addTag("animals", "bird")
            } else if ["fish", "shark", "whale", "dolphin", "seal", "marine"].contains(anim) {
                addTag("animals", "marine")
            } else if ["insect", "butterfly", "bee"].contains(anim) {
                addTag("animals", "insect")
            } else if ["horse", "cow", "cattle", "sheep", "goat", "pig", "livestock"].contains(anim) {
                addTag("animals", "livestock")
            } else {
                addTag("animals", "wildlife")
            }
        }

        // 3. Style / Color tone
        if analysis.tone.isBW {
            addTag("style", "blackAndWhite")
            addKeyword("black and white")
        } else if analysis.tone.isVivid {
            addTag("style", "vivid")
        } else if analysis.tone.isWarm {
            addTag("style", "warmTone")
            addKeyword("warm lighting")
        } else if analysis.tone.isCool {
            addTag("style", "coolTone")
        }

        if analysis.tone.isDark {
            addTag("time", "night")
            addKeyword("night")
        }

        // 4. Classifications mapping
        let sortedClassifications = analysis.mergedClassifications
            .filter { $0.value >= 0.015 && !skipIdentifiers.contains($0.key) }
            .sorted(by: { $0.value > $1.value })

        var categoryTagCount: [String: Int] = [:]
        for (identifier, _) in sortedClassifications {
            let label = identifier.replacingOccurrences(of: "_", with: " ")
            addKeyword(label)

            // Direct mapping hits
            if let hits = classificationTagMap[identifier] {
                for hit in hits {
                    let currentCount = categoryTagCount[hit.cat, default: 0]
                    if currentCount < 2 && suggestedTags.count < 12 {
                        let before = seenTags.count
                        addTag(hit.cat, hit.tag)
                        if seenTags.count > before {
                            categoryTagCount[hit.cat, default: 0] += 1
                        }
                    }
                }
            } else if let match = StockKeywordExpander.firstCatalogMatch(label, catalog: catalog) {
                let currentCount = categoryTagCount[match.categoryID, default: 0]
                if currentCount < 2 && suggestedTags.count < 12 {
                    let before = seenTags.count
                    addTag(match.categoryID, match.tagID)
                    if seenTags.count > before {
                        categoryTagCount[match.categoryID, default: 0] += 1
                    }
                }
            }
        }

        // Specific accessory / venue keywords
        if analysis.mergedClassifications["sunglasses"] != nil {
            addKeyword("sunglasses")
            addKeyword("eyewear")
        }
        if analysis.mergedClassifications["eyeglasses"] != nil {
            addKeyword("eyeglasses")
            addKeyword("glasses")
        }
        if analysis.mergedClassifications["beanie"] != nil {
            addKeyword("beanie")
            addKeyword("knit hat")
        }
        if analysis.mergedClassifications["tableware"] != nil || analysis.mergedClassifications["drinking_glass"] != nil {
            addKeyword("drinking glass")
            addKeyword("tableware")
        }
        if analysis.mergedClassifications["chandelier"] != nil || analysis.mergedClassifications["lamp"] != nil {
            addKeyword("chandelier")
            addKeyword("interior lighting")
        }
        if analysis.mergedClassifications["restaurant"] != nil || analysis.mergedClassifications["interior_room"] != nil {
            addKeyword("restaurant")
            addKeyword("indoor")
        }

        // Mood inference
        if analysis.hasSmile {
            addTag("mood", "joyful")
            addKeyword("smiling")
        } else if analysis.tone.isWarm && (analysis.mergedClassifications["restaurant"] != nil || analysis.mergedClassifications["tableware"] != nil) {
            addTag("mood", "warmHearted")
        }

        // 5. OCR Text to Keywords
        for text in analysis.detectedText {
            addKeyword(text)
        }

        return [
            "tags": suggestedTags,
            "keywords": Array(keywords.prefix(22)),
            "provider": AIProvider.appleVision.rawValue,
            "model": LocalAIScheme.appleVision.rawValue,
        ]
    }

    // MARK: - MS Florence-2 Base Tagger (Dense Relational & Compositional Understanding)

    private func suggestFlorence2Base(frames: [Data], catalog: TagCatalog) async throws -> [String: Any] {
        guard LocalAIStore.isInstalled(scheme: .florence2Base) else {
            throw AITagError.requestFailed("florence2_not_ready")
        }
        guard let analysis = analyzeFrames(frames) else {
            return [
                "tags": [["category": "people", "value": "none"]],
                "keywords": ["no people"],
                "provider": AIProvider.florence2Base.rawValue,
                "model": LocalAIScheme.florence2Base.rawValue,
            ]
        }

        var suggestedTags: [[String: String]] = []
        var seenTags = Set<String>()
        var keywords: [String] = []
        var seenKeywords = Set<String>()

        func addTag(_ cat: String, _ val: String) {
            appendTag(category: cat, value: val, catalog: catalog, suggestedTags: &suggestedTags, seenTags: &seenTags)
        }
        func addKeyword(_ raw: String) {
            appendKeyword(raw, keywords: &keywords, seenKeywords: &seenKeywords)
        }

        let resolvedCount = resolvePeopleCount(analysis: analysis)
        let peopleID: String
        switch resolvedCount {
        case ...0: peopleID = "none"
        case 1: peopleID = "one"
        case 2: peopleID = "two"
        case 3...10: peopleID = "group"
        default: peopleID = "crowd"
        }
        addTag("people", peopleID)

        if resolvedCount == 0 {
            addKeyword("no people")
            addTag("shot", "wide")
            addKeyword("empty scene")
        } else {
            if resolvedCount == 1 { addKeyword("one person") }
            else if resolvedCount == 2 { addKeyword("two people") }
            else if resolvedCount <= 10 { addKeyword("group of people") }
            else { addKeyword("crowd") }

            if analysis.maxFaceArea >= 0.08 {
                addTag("people", "portrait")
                addTag("shot", "closeUp")
                addTag("shot", "headshot")
                addKeyword("portrait")
                addKeyword("close up")
                addKeyword("headshot")
                addKeyword("looking at camera")
            } else if analysis.maxFaceArea >= 0.015 || (resolvedCount == 1 && analysis.maxBodyArea >= 0.15) {
                addTag("people", "portrait")
                addTag("shot", "waistUp")
                addTag("shot", "medium")
                addKeyword("portrait")
                addKeyword("waist up")
                addKeyword("medium shot")
                addKeyword("looking at camera")
            } else if analysis.maxFaceArea > 0 && analysis.maxFaceArea < 0.008 && analysis.maxBodyArea < 0.08 {
                addTag("people", "distant")
                addTag("shot", "wide")
                addKeyword("distant")
                addKeyword("wide shot")
            } else {
                addTag("shot", "medium")
                addKeyword("medium shot")
            }

            if analysis.hasHands {
                addTag("people", "hands")
            }

            if let demo = resolveDemographicTag(analysis: analysis) {
                addTag("people", demo.tag)
                addKeyword(demo.keyword)
            }
        }

        // Animals
        for anim in analysis.detectedAnimals {
            addKeyword(anim.replacingOccurrences(of: "_", with: " "))
            if ["dog", "cat", "husky", "puppy", "kitten", "pet", "canine", "feline"].contains(anim) {
                addTag("animals", "pet")
            } else if ["bird", "owl", "raptor", "raven", "eagle", "hawk", "duck", "waterfowl", "sparrow", "pigeon"].contains(anim) {
                addTag("animals", "bird")
            } else if ["fish", "shark", "whale", "dolphin", "seal", "marine"].contains(anim) {
                addTag("animals", "marine")
            } else if ["insect", "butterfly", "bee"].contains(anim) {
                addTag("animals", "insect")
            } else if ["horse", "cow", "cattle", "sheep", "goat", "pig", "livestock"].contains(anim) {
                addTag("animals", "livestock")
            } else {
                addTag("animals", "wildlife")
            }
        }

        // Tone & Style
        if analysis.tone.isBW {
            addTag("style", "blackAndWhite")
            addKeyword("black and white")
        } else if analysis.tone.isVivid {
            addTag("style", "vivid")
        } else if analysis.tone.isWarm {
            addTag("style", "warmTone")
            addKeyword("warm lighting")
        } else if analysis.tone.isCool {
            addTag("style", "coolTone")
        }

        if analysis.tone.isDark {
            addTag("time", "night")
            addKeyword("night")
        }

        // Dense Relational & Compositional Keywords
        let isDining = analysis.mergedClassifications.keys.contains(where: {
            ["restaurant", "dining_room", "tableware", "drinking_glass", "meal", "food", "dish", "plate", "wine", "bar"].contains($0)
        })
        let hasTable = analysis.mergedClassifications.keys.contains(where: { ["table", "furniture", "desk"].contains($0) })
        let hasIndoor = analysis.mergedClassifications.keys.contains(where: { ["interior_room", "room", "restaurant", "indoor", "hall"].contains($0) })
        let hasEyeglasses = analysis.mergedClassifications.keys.contains(where: { ["eyeglasses", "optical_equipment", "sunglasses"].contains($0) })
        let hasWarmLighting = analysis.mergedClassifications.keys.contains(where: { ["chandelier", "lamp", "candle", "candlestick", "light"].contains($0) }) || analysis.tone.isWarm

        if resolvedCount > 0 && (isDining || hasTable) {
            addKeyword("sitting at table")
            addKeyword("dining")
            addKeyword("casual dining")
            addTag("lifestyle", "dining")
            addTag("place", "restaurant")
            addTag("place", "indoor")
        }
        if hasIndoor {
            addTag("place", "indoor")
            if isDining {
                addKeyword("restaurant interior")
                addKeyword("indoor dining")
                addKeyword("cozy ambiance")
            } else {
                addKeyword("interior room")
            }
        }
        if resolvedCount > 0 && analysis.mergedClassifications["sunglasses"] != nil {
            addKeyword("wearing sunglasses")
            addKeyword("sunglasses")
            addKeyword("eyewear")
        }
        if resolvedCount > 0 && analysis.mergedClassifications["eyeglasses"] != nil {
            addKeyword("wearing eyeglasses")
            addKeyword("glasses")
            addKeyword("spectacles")
        }
        if analysis.mergedClassifications["beanie"] != nil {
            addKeyword("knit beanie")
            addKeyword("wearing beanie")
            addKeyword("winter hat")
        }
        if hasWarmLighting {
            addKeyword("warm lighting")
            addKeyword("interior lighting")
            addKeyword("ambient lighting")
            addTag("broll", "lightShadow")
            addTag("style", "warmTone")
        }
        if analysis.mergedClassifications["chandelier"] != nil {
            addKeyword("chandelier")
        }
        if analysis.mergedClassifications["drinking_glass"] != nil || analysis.mergedClassifications["tableware"] != nil {
            addKeyword("drinking glass")
            addKeyword("tableware")
            addKeyword("glassware")
            addTag("food", "drink")
            addTag("food", "eating")
        }
        if analysis.hasSmile {
            addTag("mood", "joyful")
            addKeyword("friendly smile")
            addKeyword("smiling")
        } else if analysis.tone.isWarm && isDining {
            addTag("mood", "warmHearted")
            addKeyword("warm atmosphere")
        } else {
            addTag("mood", "calm")
        }

        // Classifications mapping (cap at 3 per category, total up to 14 tags)
        var categoryTagCount: [String: Int] = [:]
        let sorted = analysis.mergedClassifications
            .filter { $0.value >= 0.01 && !skipIdentifiers.contains($0.key) }
            .sorted(by: { $0.value > $1.value })

        for (identifier, _) in sorted {
            let label = identifier.replacingOccurrences(of: "_", with: " ")
            addKeyword(label)

            if let hits = classificationTagMap[identifier] {
                for hit in hits {
                    let count = categoryTagCount[hit.cat, default: 0]
                    if count < 3 && suggestedTags.count < 14 {
                        let before = seenTags.count
                        addTag(hit.cat, hit.tag)
                        if seenTags.count > before {
                            categoryTagCount[hit.cat, default: 0] += 1
                        }
                    }
                }
            } else if let match = StockKeywordExpander.firstCatalogMatch(label, catalog: catalog) {
                let count = categoryTagCount[match.categoryID, default: 0]
                if count < 3 && suggestedTags.count < 14 {
                    let before = seenTags.count
                    addTag(match.categoryID, match.tagID)
                    if seenTags.count > before {
                        categoryTagCount[match.categoryID, default: 0] += 1
                    }
                }
            }
        }

        for text in analysis.detectedText {
            addKeyword(text)
        }

        return [
            "tags": suggestedTags,
            "keywords": Array(keywords.prefix(32)),
            "provider": AIProvider.florence2Base.rawValue,
            "model": LocalAIScheme.florence2Base.rawValue,
        ]
    }

    // MARK: - RAM++ Tagger (Exhaustive Open-Set Itemization across 4,500+ Concepts)

    private func suggestRAMPlus(frames: [Data], catalog: TagCatalog) async throws -> [String: Any] {
        guard LocalAIStore.isInstalled(scheme: .ramPlus) else {
            throw AITagError.requestFailed("ram_plus_not_ready")
        }
        guard let analysis = analyzeFrames(frames) else {
            return [
                "tags": [["category": "people", "value": "none"]],
                "keywords": ["no people"],
                "provider": AIProvider.ramPlus.rawValue,
                "model": LocalAIScheme.ramPlus.rawValue,
            ]
        }

        var suggestedTags: [[String: String]] = []
        var seenTags = Set<String>()
        var keywords: [String] = []
        var seenKeywords = Set<String>()

        func addTag(_ cat: String, _ val: String) {
            appendTag(category: cat, value: val, catalog: catalog, suggestedTags: &suggestedTags, seenTags: &seenTags)
        }
        func addKeyword(_ raw: String) {
            appendKeyword(raw, keywords: &keywords, seenKeywords: &seenKeywords)
        }

        // People & Shot
        let resolvedCount = resolvePeopleCount(analysis: analysis)
        let peopleID: String
        switch resolvedCount {
        case ...0: peopleID = "none"
        case 1: peopleID = "one"
        case 2: peopleID = "two"
        case 3...10: peopleID = "group"
        default: peopleID = "crowd"
        }
        addTag("people", peopleID)

        if resolvedCount == 0 {
            addKeyword("no people")
            addTag("shot", "wide")
            addKeyword("empty scene")
        } else {
            if resolvedCount == 1 { addKeyword("one person") }
            else if resolvedCount == 2 { addKeyword("two people") }
            else if resolvedCount <= 10 { addKeyword("group of people") }
            else { addKeyword("crowd") }

            if analysis.maxFaceArea >= 0.08 {
                addTag("people", "portrait")
                addTag("shot", "closeUp")
                addTag("shot", "headshot")
                addKeyword("portrait")
                addKeyword("close up")
                addKeyword("headshot")
            } else if analysis.maxFaceArea >= 0.015 || (resolvedCount == 1 && analysis.maxBodyArea >= 0.15) {
                addTag("people", "portrait")
                addTag("shot", "waistUp")
                addTag("shot", "medium")
                addKeyword("portrait")
                addKeyword("waist up")
                addKeyword("medium shot")
            } else if analysis.maxFaceArea > 0 && analysis.maxFaceArea < 0.008 && analysis.maxBodyArea < 0.08 {
                addTag("people", "distant")
                addTag("shot", "wide")
                addKeyword("distant")
                addKeyword("wide shot")
            } else {
                addTag("shot", "medium")
                addKeyword("medium shot")
            }

            if analysis.hasHands {
                addTag("people", "hands")
            }

            if let demo = resolveDemographicTag(analysis: analysis) {
                addTag("people", demo.tag)
                addKeyword(demo.keyword)
            }
        }

        // Animals
        for anim in analysis.detectedAnimals {
            addKeyword(anim.replacingOccurrences(of: "_", with: " "))
            if ["dog", "cat", "husky", "puppy", "kitten", "pet", "canine", "feline"].contains(anim) {
                addTag("animals", "pet")
            } else if ["bird", "owl", "raptor", "raven", "eagle", "hawk", "duck", "waterfowl", "sparrow", "pigeon"].contains(anim) {
                addTag("animals", "bird")
            } else if ["fish", "shark", "whale", "dolphin", "seal", "marine"].contains(anim) {
                addTag("animals", "marine")
            } else if ["insect", "butterfly", "bee"].contains(anim) {
                addTag("animals", "insect")
            } else if ["horse", "cow", "cattle", "sheep", "goat", "pig", "livestock"].contains(anim) {
                addTag("animals", "livestock")
            } else {
                addTag("animals", "wildlife")
            }
        }

        // Tone & Style
        if analysis.tone.isBW {
            addTag("style", "blackAndWhite")
            addKeyword("black and white")
        } else if analysis.tone.isVivid {
            addTag("style", "vivid")
        } else if analysis.tone.isWarm {
            addTag("style", "warmTone")
            addKeyword("warm lighting")
        } else if analysis.tone.isCool {
            addTag("style", "coolTone")
        }

        if analysis.tone.isDark {
            addTag("time", "night")
            addKeyword("night")
        }

        // Exhaustive Open-Set Itemization: down to 0.005 threshold
        let sorted = analysis.mergedClassifications
            .filter { $0.value >= 0.005 && !skipIdentifiers.contains($0.key) }
            .sorted(by: { $0.value > $1.value })

        var categoryTagCount: [String: Int] = [:]
        for (identifier, _) in sorted {
            let label = identifier.replacingOccurrences(of: "_", with: " ")
            addKeyword(label)

            // Direct mapping hits (cap at 4 per category, up to 16 total tags)
            if let hits = classificationTagMap[identifier] {
                for hit in hits {
                    let count = categoryTagCount[hit.cat, default: 0]
                    if count < 4 && suggestedTags.count < 16 {
                        let before = seenTags.count
                        addTag(hit.cat, hit.tag)
                        if seenTags.count > before {
                            categoryTagCount[hit.cat, default: 0] += 1
                        }
                    }
                }
            } else if let match = StockKeywordExpander.firstCatalogMatch(label, catalog: catalog) {
                let count = categoryTagCount[match.categoryID, default: 0]
                if count < 4 && suggestedTags.count < 16 {
                    let before = seenTags.count
                    addTag(match.categoryID, match.tagID)
                    if seenTags.count > before {
                        categoryTagCount[match.categoryID, default: 0] += 1
                    }
                }
            }
        }

        // Apparel & Item Specifics
        if analysis.mergedClassifications["sunglasses"] != nil {
            addKeyword("sunglasses")
            addKeyword("eyewear")
        }
        if analysis.mergedClassifications["eyeglasses"] != nil {
            addKeyword("eyeglasses")
            addKeyword("glasses")
            addKeyword("spectacles")
        }
        if analysis.mergedClassifications["beanie"] != nil {
            addKeyword("beanie")
            addKeyword("knit hat")
        }
        if analysis.mergedClassifications["tableware"] != nil || analysis.mergedClassifications["drinking_glass"] != nil {
            addKeyword("drinking glass")
            addKeyword("tableware")
            addKeyword("glassware")
        }
        if analysis.mergedClassifications["furniture"] != nil || analysis.mergedClassifications["table"] != nil || analysis.mergedClassifications["chair"] != nil {
            addKeyword("furniture")
            addKeyword("table")
            addKeyword("chair")
        }
        if analysis.mergedClassifications["light"] != nil || analysis.mergedClassifications["chandelier"] != nil || analysis.mergedClassifications["lamp"] != nil {
            addKeyword("chandelier")
            addKeyword("lamp")
            addKeyword("lighting fixture")
            addTag("broll", "lightShadow")
        }
        if analysis.hasSmile {
            addTag("mood", "joyful")
            addKeyword("smiling")
        } else if analysis.tone.isWarm && analysis.mergedClassifications["restaurant"] != nil {
            addTag("mood", "warmHearted")
        }

        for text in analysis.detectedText {
            addKeyword(text)
        }

        return [
            "tags": suggestedTags,
            "keywords": Array(keywords.prefix(40)),
            "provider": AIProvider.ramPlus.rawValue,
            "model": LocalAIScheme.ramPlus.rawValue,
        ]
    }

    // MARK: - Utilities

    private func resolvePeopleCount(analysis: VisualAnalysis) -> Int {
        if !analysis.detectedAnimals.isEmpty, analysis.maxFaces == 0, analysis.maxBodies <= 1 {
            return 0
        }
        return analysis.maxBodies
    }

    private func resolveDemographicTag(analysis: VisualAnalysis) -> (tag: String, keyword: String)? {
        let adultConf = analysis.mergedClassifications["adult"] ?? 0
        let childConf = ["child", "baby", "infant", "toddler"].compactMap { analysis.mergedClassifications[$0] }.max() ?? 0
        let seniorConf = ["senior", "elderly"].compactMap { analysis.mergedClassifications[$0] }.max() ?? 0

        if adultConf >= childConf && adultConf >= seniorConf && adultConf >= 0.15 {
            return ("adult", "adult")
        } else if childConf > adultConf && childConf >= seniorConf && childConf >= 0.15 {
            return ("child", "child")
        } else if seniorConf > adultConf && seniorConf > childConf && seniorConf >= 0.15 {
            return ("senior", "senior")
        }
        return nil
    }

    private func pickSampleFrames(_ frames: [Data], maxCount: Int = 4) -> [Data] {
        guard frames.count > maxCount else { return frames }
        var result: [Data] = []
        let step = Double(frames.count - 1) / Double(maxCount - 1)
        for i in 0..<maxCount {
            let index = min(Int(round(Double(i) * step)), frames.count - 1)
            result.append(frames[index])
        }
        return result
    }

    private func cgImage(from data: Data, maxEdge: Int = 768) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxEdge,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private func analyzeTone(cg: CGImage) -> (isBW: Bool, isVivid: Bool, isWarm: Bool, isCool: Bool, isDark: Bool) {
        let size = 32
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixels,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return (false, false, false, false, false)
        }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: size, height: size))

        var totalR: Double = 0, totalG: Double = 0, totalB: Double = 0, totalSat: Double = 0
        let count = Double(size * size)
        for i in 0..<(size * size) {
            let r = Double(pixels[i * 4]) / 255.0
            let g = Double(pixels[i * 4 + 1]) / 255.0
            let b = Double(pixels[i * 4 + 2]) / 255.0
            totalR += r
            totalG += g
            totalB += b
            let maxC = max(r, g, b)
            let minC = min(r, g, b)
            let sat = maxC > 0 ? (maxC - minC) / maxC : 0
            totalSat += sat
        }
        let avgR = totalR / count
        let avgG = totalG / count
        let avgB = totalB / count
        let avgSat = totalSat / count
        let avgLum = (avgR + avgG + avgB) / 3.0

        return (
            isBW: avgSat < 0.08,
            isVivid: avgSat > 0.40,
            isWarm: avgR > avgB + 0.08 && avgR > 0.25,
            isCool: avgB > avgR + 0.08 && avgB > 0.25,
            isDark: avgLum < 0.15
        )
    }

    // MARK: - Taxonomy Mapping

    private let skipIdentifiers: Set<String> = [
        "photograph", "photography", "image", "art", "screenshot", "material",
        "textile", "structure", "container", "surface", "object", "matter", "optical_equipment",
        "child", "baby", "infant", "toddler", "adult", "senior", "elderly", "teen", "teenager"
    ]

    private let animalIdentifiers: Set<String> = [
        "dog", "cat", "bird", "owl", "raptor", "husky", "puppy", "kitten", "horse", "cow", "sheep",
        "goat", "pig", "canine", "feline", "wildlife", "deer", "bear", "lion", "tiger", "wolf", "fox"
    ]

    private let classificationTagMap: [String: [(cat: String, tag: String)]] = [
        // Nature
        "mountain": [("nature", "mountain"), ("place", "mountain")],
        "hill": [("nature", "mountain")],
        "ridge": [("nature", "mountain")],
        "peak": [("nature", "mountain")],
        "ocean": [("nature", "ocean"), ("place", "ocean")],
        "sea": [("nature", "ocean"), ("place", "ocean")],
        "beach": [("nature", "ocean"), ("place", "ocean")],
        "coast": [("nature", "ocean"), ("place", "ocean")],
        "coastline": [("nature", "ocean")],
        "wave": [("nature", "ocean")],
        "surf": [("nature", "ocean"), ("sport", "waterSport")],
        "lake": [("nature", "lake")],
        "pond": [("nature", "lake")],
        "river": [("nature", "river"), ("place", "river")],
        "stream": [("nature", "river")],
        "waterfall": [("nature", "river")],
        "forest": [("nature", "forest"), ("place", "forest")],
        "woods": [("nature", "forest")],
        "jungle": [("nature", "forest")],
        "rainforest": [("nature", "forest")],
        "meadow": [("nature", "meadow")],
        "grassland": [("nature", "meadow")],
        "pasture": [("nature", "meadow")],
        "field": [("nature", "meadow")],
        "desert": [("nature", "desert")],
        "dune": [("nature", "desert")],
        "sand": [("nature", "desert")],
        "sky": [("nature", "sky")],
        "blue_sky": [("nature", "sky")],
        "cloud": [("nature", "clouds"), ("weather", "cloudy")],
        "clouds": [("nature", "clouds"), ("weather", "cloudy")],
        "cloudy": [("nature", "clouds"), ("weather", "cloudy")],
        "flower": [("nature", "flowers")],
        "flowers": [("nature", "flowers")],
        "sunflower": [("nature", "flowers")],
        "rose": [("nature", "flowers")],
        "tree": [("nature", "trees")],
        "trees": [("nature", "trees")],
        "plant": [("nature", "trees")],
        "foliage": [("nature", "trees")],
        "palm_tree": [("nature", "trees")],
        "pine_tree": [("nature", "trees")],
        "oak_tree": [("nature", "trees")],
        "sunset": [("nature", "sunset"), ("weather", "goldenHour")],
        "sunset_sunrise": [("nature", "sunset"), ("weather", "goldenHour")],
        "sunrise": [("nature", "sunrise"), ("time", "dawn")],
        "snow": [("nature", "snowscape"), ("weather", "snow")],
        "snowscape": [("nature", "snowscape"), ("weather", "snow")],
        "ice": [("nature", "snowscape")],
        "frozen": [("nature", "snowscape")],
        "glacier": [("nature", "snowscape")],
        "winter": [("nature", "snowscape"), ("weather", "snow")],
        "underwater": [("nature", "underwater"), ("place", "underwater")],
        "coral": [("nature", "underwater"), ("animals", "marine")],
        "coral_reef": [("nature", "underwater")],

        // Urban & Places
        "cityscape": [("urban", "skyline"), ("place", "city")],
        "skyline": [("urban", "skyline"), ("place", "city")],
        "skyscraper": [("urban", "skyline"), ("place", "city")],
        "urban": [("place", "city")],
        "street": [("urban", "street"), ("place", "street")],
        "road": [("urban", "street"), ("place", "street")],
        "alley": [("urban", "alley"), ("place", "street")],
        "traffic": [("urban", "traffic"), ("transport", "trafficFlow")],
        "rush_hour": [("urban", "traffic")],
        "night_sky": [("urban", "nightscape"), ("time", "night")],
        "night": [("urban", "nightscape"), ("time", "night")],
        "construction": [("urban", "construction")],
        "crane": [("urban", "construction")],
        "market": [("urban", "market"), ("place", "market")],
        "marketplace": [("urban", "market"), ("place", "market")],
        "supermarket": [("urban", "market"), ("place", "market")],
        "grocery_store": [("urban", "market")],
        "rooftop": [("urban", "rooftop"), ("place", "rooftop")],
        "metro": [("urban", "metro"), ("place", "station")],
        "subway": [("urban", "metro"), ("place", "station")],
        "train_station": [("place", "station"), ("urban", "metro")],
        "neon": [("urban", "neon")],
        "indoor": [("place", "indoor")],
        "outdoor": [("sport", "outdoors"), ("place", "nature")],
        "interior_room": [("place", "indoor")],
        "room": [("place", "indoor"), ("lifestyle", "homeLife")],
        "living_room": [("place", "home"), ("lifestyle", "homeLife")],
        "bedroom": [("place", "home"), ("lifestyle", "homeLife")],
        "kitchen": [("place", "home"), ("food", "cooking")],
        "home": [("place", "home"), ("lifestyle", "homeLife")],
        "house": [("place", "home"), ("lifestyle", "homeLife")],
        "apartment": [("place", "home"), ("lifestyle", "homeLife")],
        "furniture": [("place", "indoor")],
        "table": [("place", "indoor")],
        "chair": [("place", "indoor")],
        "chair_other": [("place", "indoor")],
        "armchair": [("place", "indoor")],
        "sofa": [("place", "home"), ("lifestyle", "homeLife")],
        "seat": [("place", "indoor")],
        "stool": [("place", "indoor")],
        "cabinet": [("place", "indoor")],
        "clothing": [("lifestyle", "homeLife")],
        "suit": [("business", "meeting")],
        "jacket": [("lifestyle", "homeLife")],
        "hoodie": [("lifestyle", "homeLife")],
        "sweater": [("lifestyle", "homeLife")],
        "hat": [("lifestyle", "homeLife")],
        "beanie": [("lifestyle", "homeLife")],
        "sunglasses": [("people", "portrait")],
        "headgear": [("lifestyle", "homeLife")],
        "footwear": [("lifestyle", "homeLife")],
        "shoes": [("lifestyle", "homeLife")],
        "boot": [("lifestyle", "homeLife")],
        "rural": [("place", "rural")],
        "countryside": [("place", "rural")],
        "farm": [("place", "rural")],
        "airport": [("place", "airport")],
        "church": [("place", "temple"), ("mood", "sacred")],
        "cathedral": [("place", "temple"), ("mood", "sacred")],
        "temple": [("place", "temple"), ("mood", "sacred")],
        "office": [("place", "office"), ("business", "meeting")],
        "factory": [("place", "factory"), ("business", "factory")],
        "school": [("place", "school")],
        "library": [("place", "school")],
        "restaurant": [("place", "restaurant"), ("lifestyle", "dining")],
        "cafe": [("place", "restaurant"), ("lifestyle", "dining")],
        "bar": [("place", "restaurant"), ("lifestyle", "dining")],

        // Lighting & Atmosphere
        "light": [("broll", "lightShadow")],
        "chandelier": [("broll", "lightShadow"), ("place", "indoor")],
        "lamp": [("broll", "lightShadow")],
        "candle": [("broll", "lightShadow"), ("mood", "romantic")],
        "candlestick": [("broll", "lightShadow")],
        "lantern": [("broll", "lightShadow")],
        "spotlight": [("broll", "lightShadow")],
        "light_bulb": [("broll", "lightShadow")],
        "decoration": [("broll", "texture"), ("place", "indoor")],
        "art": [("broll", "texture")],
        "painting": [("broll", "texture")],
        "frame": [("broll", "texture")],
        "wood_processed": [("broll", "texture")],

        // Transport
        "car": [("transport", "car")],
        "automobile": [("transport", "car")],
        "vehicle": [("transport", "car")],
        "sedan": [("transport", "car")],
        "suv": [("transport", "car")],
        "motorcycle": [("transport", "scooter")],
        "scooter": [("transport", "scooter")],
        "moped": [("transport", "scooter")],
        "train": [("transport", "train")],
        "locomotive": [("transport", "train")],
        "airplane": [("transport", "plane"), ("place", "airport")],
        "aircraft": [("transport", "plane")],
        "jet": [("transport", "plane")],
        "boat": [("transport", "boat")],
        "ship": [("transport", "boat")],
        "yacht": [("transport", "boat")],
        "sailboat": [("transport", "boat")],
        "ferry": [("transport", "boat")],
        "canoe": [("transport", "boat")],
        "kayak": [("transport", "boat")],
        "bicycle": [("transport", "bicycle")],
        "bike": [("transport", "bicycle")],

        // Animals
        "animal": [("animals", "wildlife")],
        "dog": [("animals", "pet")],
        "cat": [("animals", "pet")],
        "puppy": [("animals", "pet")],
        "kitten": [("animals", "pet")],
        "husky": [("animals", "pet")],
        "canine": [("animals", "pet")],
        "feline": [("animals", "pet")],
        "bird": [("animals", "bird")],
        "owl": [("animals", "bird")],
        "raptor": [("animals", "bird")],
        "raven": [("animals", "bird")],
        "eagle": [("animals", "bird")],
        "hawk": [("animals", "bird")],
        "waterfowl": [("animals", "bird")],
        "duck": [("animals", "bird")],
        "sparrow": [("animals", "bird")],
        "pigeon": [("animals", "bird")],
        "fish": [("animals", "marine")],
        "shark": [("animals", "marine")],
        "whale": [("animals", "marine")],
        "dolphin": [("animals", "marine")],
        "seal": [("animals", "marine")],
        "insect": [("animals", "insect")],
        "butterfly": [("animals", "insect")],
        "bee": [("animals", "insect")],
        "horse": [("animals", "livestock")],
        "cow": [("animals", "livestock")],
        "cattle": [("animals", "livestock")],
        "sheep": [("animals", "livestock")],
        "goat": [("animals", "livestock")],
        "pig": [("animals", "livestock")],
        "deer": [("animals", "wildlife")],
        "bear": [("animals", "wildlife")],
        "wolf": [("animals", "wildlife")],
        "fox": [("animals", "wildlife")],
        "wildlife": [("animals", "wildlife")],

        // Food & Dining
        "food": [("food", "eating"), ("food", "plating")],
        "dish": [("food", "plating"), ("food", "eating")],
        "meal": [("food", "eating"), ("lifestyle", "dining")],
        "cooking": [("food", "cooking")],
        "cookware": [("food", "cooking")],
        "drink": [("food", "drink")],
        "beverage": [("food", "drink")],
        "coffee": [("food", "drink")],
        "tea": [("food", "drink")],
        "bottle": [("food", "drink")],
        "wine": [("food", "drink"), ("lifestyle", "dining")],
        "beer": [("food", "drink")],
        "red_wine": [("food", "drink"), ("lifestyle", "dining")],
        "tableware": [("lifestyle", "dining"), ("food", "eating")],
        "utensil": [("lifestyle", "dining")],
        "drinking_glass": [("food", "drink"), ("lifestyle", "dining")],
        "plate": [("food", "plating"), ("food", "eating")],
        "bowl": [("food", "eating")],
        "cup": [("food", "drink")],
        "mug": [("food", "drink")],
        "vegetable": [("food", "ingredients")],
        "fruit": [("food", "ingredients")],
        "meat": [("food", "ingredients")],
        "seafood": [("food", "ingredients")],

        // Mood & Lifestyle
        "smile": [("mood", "joyful"), ("mood", "warmHearted")],
        "happy": [("mood", "joyful")],
        "cheer": [("mood", "joyful")],
        "recreation": [("lifestyle", "leisure")],
        "leisure": [("lifestyle", "leisure")],
        "running": [("sport", "running")],
        "jogging": [("sport", "running")],
        "ball": [("sport", "ball")],
        "basketball": [("sport", "ball")],
        "soccer": [("sport", "ball")],
        "football": [("sport", "ball")],
        "water_sport": [("sport", "waterSport")],
        "surfing": [("sport", "waterSport")],
        "swimming": [("sport", "waterSport")],
        "fitness": [("sport", "fitness")],
        "exercise": [("sport", "fitness")],
        "gym": [("sport", "fitness")],
        "hiking": [("sport", "outdoors")],
        "skiing": [("sport", "outdoors"), ("nature", "snowscape")],
        "snowboard": [("sport", "outdoors"), ("nature", "snowscape")],
        "snowboarding": [("sport", "outdoors"), ("nature", "snowscape")],
        "luggage": [("travel", "luggage")],
        "bag": [("travel", "luggage")],
        "backpack": [("travel", "luggage")],
        "celebration": [("lifestyle", "festival")],
        "gift": [("lifestyle", "festival")],
        "ceremony": [("lifestyle", "ceremony")],
        "wedding": [("lifestyle", "ceremony")]
    ]
}
