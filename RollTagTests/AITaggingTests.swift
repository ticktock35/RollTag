import AppKit
import XCTest
@testable import RollTag

final class AITaggingTests: XCTestCase {
    func testGeminiThenOpenAIWhenAuto() {
        var ai = AIPreference.empty
        ai = withKeys(ai, gemini: "g", openai: "o")
        XCTAssertEqual(ai.taggingRoute()?.provider, .gemini)
        XCTAssertEqual(ai.resolvedModel(for: .gemini), "gemini-3.5-flash-lite")
        XCTAssertEqual(ai.resolvedModel(for: .openai), "gpt-4.1-mini")
        XCTAssertEqual(ai.taggingRoutes().map(\.provider), [.gemini, .openai])
    }

    func testFallsBackToOpenAIWithoutGeminiKey() {
        var ai = AIPreference.empty
        ai.providers[.openai] = AIProviderSettings(apiKey: "o", model: "")
        XCTAssertEqual(ai.taggingRoute()?.provider, .openai)
        XCTAssertEqual(ai.taggingRoute()?.model, "gpt-4.1-mini")
    }

    func testSelectedOpenAIGoesFirstButGeminiStaysFallback() {
        var ai = AIPreference.empty
        ai.selectedProvider = .openai
        ai = withKeys(ai, gemini: "g", openai: "o")
        XCTAssertEqual(ai.taggingRoutes().map(\.provider), [.openai, .gemini])
    }

    func testCustomModelOverridesDefault() {
        var ai = AIPreference.empty
        ai.providers[.gemini] = AIProviderSettings(apiKey: "g", model: "gemini-3.5-flash")
        XCTAssertEqual(ai.resolvedModel(for: .gemini), "gemini-3.5-flash")
        XCTAssertEqual(ai.displayedModel(for: .gemini), "gemini-3.5-flash")
    }

    func testSelectableModelsAreCapableEnoughAndKeepUnknownStored() {
        XCTAssertEqual(AIProvider.gemini.selectableModels.first, "gemini-3.5-flash-lite")
        XCTAssertEqual(AIProvider.openai.selectableModels.first, "gpt-4.1-mini")
        XCTAssertTrue(AIProvider.gemini.selectableModels.contains("gemini-3.5-flash"))
        XCTAssertTrue(AIProvider.openai.selectableModels.contains("gpt-4.1"))
        XCTAssertFalse(AIProvider.gemini.selectableModels.contains("gemini-2.5-flash-lite"))
        XCTAssertFalse(AIProvider.openai.selectableModels.contains("gpt-4o-mini"))
        XCTAssertEqual(
            AIProvider.gemini.pickerModels(stored: "legacy-custom"),
            AIProvider.gemini.selectableModels + ["legacy-custom"]
        )
        var ai = AIPreference.empty
        XCTAssertEqual(ai.displayedModel(for: .gemini), "gemini-3.5-flash-lite")
        ai.providers[.gemini] = AIProviderSettings(apiKey: "g", model: "gemini-2.5-flash-lite")
        XCTAssertEqual(ai.resolvedModel(for: .gemini), "gemini-3.5-flash-lite")
        XCTAssertEqual(AIProvider.gemini.pickerModels(stored: "gemini-2.5-flash-lite"), AIProvider.gemini.selectableModels)
    }

    func testUnwiredSelectionStillUsesFrameProviders() {
        var ai = AIPreference.empty
        ai.selectedProvider = .twelvelabs
        ai = withKeys(ai, gemini: "g", openai: "")
        XCTAssertEqual(ai.taggingRoute()?.provider, .gemini)
    }

    func testContextSendsKnownFileFactsAndOmitsMissingGPS() {
        let footage = Footage(
            id: UUID(),
            warehouseID: UUID(),
            relativePath: "malaysia/street.mov",
            filename: "street.mov",
            size: 1_024_000,
            mtime: 1,
            contentHash: "h",
            phash: nil,
            status: .available,
            duration: 12.5,
            width: 1920,
            height: 1080,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            parentID: nil,
            userNotes: "",
            tags: [],
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let payload = AITagSuggester.contextPayload(footage: footage, warehouseName: "Travel")
        XCTAssertEqual(payload["filename"] as? String, "street.mov")
        XCTAssertEqual(payload["relative_path"] as? String, "malaysia/street.mov")
        XCTAssertEqual(payload["directory"] as? String, "malaysia")
        XCTAssertEqual(payload["warehouse_name"] as? String, "Travel")
        XCTAssertEqual((payload["file_size_bytes"] as? NSNumber)?.int64Value, 1_024_000)
        XCTAssertEqual((payload["duration_seconds"] as? NSNumber)?.doubleValue, 12.5)
        XCTAssertNotNil(payload["captured_at"] as? String)
        XCTAssertNil(payload["gps"])
    }

    func testContextIncludesLiveGPS() {
        let footage = Footage(
            id: UUID(),
            warehouseID: UUID(),
            relativePath: "clip.mp4",
            filename: "clip.mp4",
            size: 10,
            mtime: 1,
            contentHash: nil,
            phash: nil,
            status: .available,
            duration: nil,
            width: nil,
            height: nil,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            parentID: nil,
            userNotes: "",
            tags: [],
            capturedAt: nil
        )
        let live = MediaMetadataSnapshot(latitude: -1.3, longitude: 103.8, altitude: 12, capturedAt: nil)
        let payload = AITagSuggester.contextPayload(footage: footage, warehouseName: "A", live: live)
        let gps = payload["gps"] as? [String: Any]
        XCTAssertEqual(gps?["latitude"] as? Double, -1.3)
        XCTAssertEqual(gps?["longitude"] as? Double, 103.8)
        XCTAssertEqual(gps?["altitude"] as? Double, 12)
    }

    func testISO6709LocationParse() {
        let everest = MediaMetadata.parseISO6709("+27.5916+086.5640+8850.000/")
        XCTAssertEqual(everest?.latitude ?? 0, 27.5916, accuracy: 0.0001)
        XCTAssertEqual(everest?.longitude ?? 0, 86.5640, accuracy: 0.0001)
        XCTAssertEqual(everest?.altitude ?? 0, 8850, accuracy: 0.1)
        let west = MediaMetadata.parseISO6709("-1.3-103.8/")
        XCTAssertEqual(west?.latitude ?? 0, -1.3, accuracy: 0.01)
        XCTAssertEqual(west?.longitude ?? 0, -103.8, accuracy: 0.01)
        XCTAssertEqual(MediaMetadata.signedCoordinate(3.2, reference: "S", southOrWest: "S"), -3.2)
        XCTAssertEqual(MediaMetadata.signedCoordinate(100, reference: "E", southOrWest: "W"), 100)
    }

    func testAssignmentsDropUnknownAndDuplicates() {
        let catalog = TagCatalog(categories: [
            TagCategory(
                id: "nature",
                names: ["en": "Nature"],
                tags: [TagDefinition(id: "ocean", names: ["en": "Ocean"])]
            ),
        ])
        let tags = AITagSuggester.assignments(
            from: [
                ["category": "nature", "value": "ocean"],
                ["category": "nature", "value": "ocean"],
                ["category": "nature", "value": "volcano"],
                ["category": "custom", "value": "測試"],
                ["category": "custom", "value": "invented"],
            ],
            catalog: catalog,
            customValues: ["測試"]
        )
        XCTAssertEqual(tags, [
            .ai(category: "nature", value: "ocean"),
            .ai(category: "custom", value: "測試"),
        ])
    }

    func testAssignmentsKeepGettyKeywordsAndVisibleChinese() {
        let catalog = TagCatalog(categories: [
            TagCategory(
                id: "nature",
                names: ["en": "Nature"],
                tags: [TagDefinition(id: "ocean", names: ["en": "Ocean", "zh-Hant": "海"])]
            ),
        ])
        let payload: [String: Any] = [
            "tags": [
                ["category": "nature", "value": "ocean"],
                ["category": "custom", "value": "破冰船"],
                ["category": "custom", "value": "invented"],
            ],
            "keywords": ["Icebreaker", "arctic ocean", "!!", "ab"],
        ]
        let tags = AITagSuggester.assignments(from: payload, catalog: catalog, customValues: [])
        XCTAssertTrue(tags.contains { $0.category == "nature" && $0.value == "ocean" })
        XCTAssertTrue(tags.contains { $0.isCustom && $0.value == "破冰船" })
        XCTAssertTrue(tags.contains { $0.isCustom && $0.value == "icebreaker" })
        XCTAssertTrue(tags.contains { $0.isCustom && $0.value == "arctic ocean" })
        XCTAssertFalse(tags.contains { $0.value == "invented" })
    }

    func testCatalogPayloadIncludesEnglishNames() {
        let catalog = TagCatalog(categories: [
            TagCategory(
                id: "nature",
                names: ["zh-Hant": "自然", "en": "Nature"],
                tags: [TagDefinition(id: "ocean", names: ["zh-Hant": "海", "en": "Ocean"])]
            ),
        ])
        let payload = AITagSuggester.catalogPayload(catalog: catalog, locale: "zh-Hant", customValues: [])
        let categories = payload["categories"] as? [[String: Any]]
        let tags = categories?.first?["tags"] as? [[String: Any]]
        XCTAssertEqual(tags?.first?["id"] as? String, "ocean")
        XCTAssertEqual(tags?.first?["name"] as? String, "海")
        XCTAssertEqual(tags?.first?["en"] as? String, "Ocean")
    }

    func testPreviewUsesParallelQuickLookPath() {
        XCTAssertEqual(ThumbnailService.analyzeConcurrency, 2)
        XCTAssertEqual(ThumbnailService.previewSize.width, 480)
    }

    func testPreviewAspectClampsUnusualImageSizes() {
        XCTAssertEqual(PreviewLayout.aspect(width: 1920, height: 1080), 16 / 9, accuracy: 0.001)
        XCTAssertEqual(PreviewLayout.aspect(width: 8000, height: 800), PreviewLayout.widest, accuracy: 0.001)
        XCTAssertEqual(PreviewLayout.aspect(width: 800, height: 4000), PreviewLayout.tallest, accuracy: 0.001)
        XCTAssertEqual(PreviewLayout.aspect(width: nil, height: 100), PreviewLayout.videoFallback, accuracy: 0.001)
        let portrait = PreviewLayout.fit(aspect: 0.75, maxWidth: 280, maxHeight: 400)
        XCTAssertEqual(portrait.width, 280, accuracy: 0.5)
        XCTAssertEqual(portrait.height, 280 / 0.75, accuracy: 0.5)
        let tall = PreviewLayout.fit(aspect: PreviewLayout.tallest, maxWidth: 280, maxHeight: 400)
        XCTAssertEqual(tall.height, 400, accuracy: 0.5)
        XCTAssertEqual(tall.width, 400 * PreviewLayout.tallest, accuracy: 0.5)
    }

    func testEnsureImageThumbnailWritesFileBeforeSecondUse() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rolltag-thumb-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let source = dir.appendingPathComponent("src.png")
        let dest = dir.appendingPathComponent("thumb.jpg")
        let image = NSImage(size: NSSize(width: 8, height: 8))
        image.lockFocus()
        NSColor.red.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 8, height: 8)).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else {
            return XCTFail("could not write fixture png")
        }
        try png.write(to: source)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path))
        let first = await ThumbnailService.ensureImageThumbnail(source: source, thumbnailURL: dest)
        XCTAssertNotNil(first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path))
        let second = await ThumbnailService.ensureImageThumbnail(source: source, thumbnailURL: dest)
        XCTAssertNotNil(second)
    }

    func testImagesSkipScanThumbnailUnlessReanalysis() {
        let fresh = snapshot(filename: "IMG_0001.HEIC", needsReanalysis: true, phash: nil)
        let done = snapshot(filename: "IMG_0001.HEIC", needsReanalysis: false, phash: nil)
        XCTAssertTrue(ThumbnailService.shouldAnalyze(fresh, thumbExists: false))
        XCTAssertFalse(ThumbnailService.shouldAnalyze(done, thumbExists: false))

        let videoNeedsDuration = snapshot(filename: "clip.mov", needsReanalysis: false, phash: nil, duration: nil)
        let videoReady = snapshot(filename: "clip.mov", needsReanalysis: false, phash: nil, duration: 12)
        XCTAssertTrue(ThumbnailService.shouldAnalyze(videoNeedsDuration, thumbExists: false))
        XCTAssertFalse(ThumbnailService.shouldAnalyze(videoReady, thumbExists: false))
    }

    private func snapshot(filename: String, needsReanalysis: Bool, phash: String?, duration: Double? = nil) -> FootageSnapshot {
        FootageSnapshot(
            id: UUID(),
            relativePath: filename,
            filename: filename,
            size: 10,
            mtime: 1,
            contentHash: "h",
            phash: phash,
            status: .available,
            tags: [],
            userNotes: "",
            parentID: nil,
            duration: duration,
            width: nil,
            height: nil,
            capturedAt: nil,
            needsReanalysis: needsReanalysis
        )
    }

    func testFrameFractionsStayInsideClip() {
        let fractions = FrameExtractor.sampleFractions(count: 6)
        XCTAssertEqual(fractions.count, 6)
        XCTAssertEqual(fractions.first ?? -1, 0.05, accuracy: 0.001)
        XCTAssertEqual(fractions.last ?? -1, 0.95, accuracy: 0.001)
        XCTAssertEqual(fractions, fractions.sorted())
        XCTAssertTrue(fractions.allSatisfy { $0 >= 0.049 && $0 <= 0.951 })
    }

    private func withKeys(_ ai: AIPreference, gemini: String, openai: String) -> AIPreference {
        var next = ai
        if !gemini.isEmpty {
            next.providers[.gemini] = AIProviderSettings(apiKey: gemini, model: "")
        }
        if !openai.isEmpty {
            next.providers[.openai] = AIProviderSettings(apiKey: openai, model: "")
        }
        return next
    }
}
