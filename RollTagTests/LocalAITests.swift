import AppKit
import XCTest
@testable import RollTag

final class LocalAITests: XCTestCase {
    func testLocalAISchemesAndProviders() {
        XCTAssertEqual(LocalAIScheme.allCases, [.appleVision, .florence2Base, .ramPlus])
        XCTAssertEqual(LocalAIScheme.appleVision.rawValue, "apple_vision")
        XCTAssertEqual(LocalAIScheme.florence2Base.rawValue, "florence2_base")
        XCTAssertEqual(LocalAIScheme.ramPlus.rawValue, "ram_plus")

        XCTAssertTrue(AIProvider.appleVision.isLocal)
        XCTAssertFalse(AIProvider.appleVision.needsAPIKey)
        XCTAssertTrue(AIProvider.appleVision.supportsFrameTagging)

        XCTAssertTrue(AIProvider.florence2Base.isLocal)
        XCTAssertFalse(AIProvider.florence2Base.needsAPIKey)
        XCTAssertTrue(AIProvider.florence2Base.supportsFrameTagging)

        XCTAssertTrue(AIProvider.ramPlus.isLocal)
        XCTAssertFalse(AIProvider.ramPlus.needsAPIKey)
        XCTAssertTrue(AIProvider.ramPlus.supportsFrameTagging)
    }

    func testLocalAIStorePathsAndInstallation() {
        XCTAssertEqual(LocalAIStore.modelsRoot.lastPathComponent, "models")
        XCTAssertEqual(LocalAIStore.florence2Root.lastPathComponent, "florence2")
        XCTAssertEqual(LocalAIStore.ramPlusRoot.lastPathComponent, "ram_plus")

        // Apple Vision is native, always installed
        XCTAssertTrue(LocalAIStore.isInstalled(scheme: .appleVision))
        XCTAssertNil(LocalAIStore.modelURL(for: .appleVision))
        XCTAssertNil(LocalAIStore.downloadURL(for: .appleVision))
        XCTAssertEqual(LocalAIStore.modelSizeString(for: .appleVision), "0 GB")

        XCTAssertEqual(LocalAIStore.modelURL(for: .florence2Base)?.lastPathComponent, "model.onnx")
        XCTAssertNotNil(LocalAIStore.downloadURL(for: .florence2Base))
        XCTAssertEqual(LocalAIStore.modelSizeString(for: .florence2Base), "~370 MB")

        XCTAssertEqual(LocalAIStore.modelURL(for: .ramPlus)?.lastPathComponent, "model.onnx")
        XCTAssertNotNil(LocalAIStore.downloadURL(for: .ramPlus))
        XCTAssertEqual(LocalAIStore.modelSizeString(for: .ramPlus), "~2.8 GB")
    }

    func testTaggingRoutesOptions() {
        var pref = AIPreference()
        pref.localAIEnabled = true
        pref.localAIScheme = .florence2Base
        pref.openaiApiKey = "sk-test"
        pref.openaiModel = "gpt-4.1-mini"

        // Default: Florence-2 Base first, then OpenAI
        let defaultRoutes = pref.taggingRoutes()
        XCTAssertEqual(defaultRoutes.count, 2)
        XCTAssertEqual(defaultRoutes[0].provider, .florence2Base)
        XCTAssertEqual(defaultRoutes[1].provider, .openai)

        // Override local scheme to Apple Vision
        let overridden = pref.taggingRoutes(overrideLocalScheme: .appleVision)
        XCTAssertEqual(overridden.count, 2)
        XCTAssertEqual(overridden[0].provider, .appleVision)
        XCTAssertEqual(overridden[1].provider, .openai)

        // Skip local AI: only cloud routes
        let skipped = pref.taggingRoutes(skipLocalAI: true)
        XCTAssertEqual(skipped.count, 1)
        XCTAssertEqual(skipped[0].provider, .openai)
    }

    func testLocalAIInstallerCancel() async {
        let installer = LocalAIInstaller.shared
        await installer.cancel(scheme: .florence2Base)
        let isDownloading = await installer.isDownloading(scheme: .florence2Base)
        XCTAssertFalse(isDownloading)
    }

    func testCleanupLegacyJoyTagRemovesFolders() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("rolltag-test-\(UUID().uuidString)")
        let joytagDir = tempDir.appendingPathComponent("joytag")
        let modelsJoytagDir = tempDir.appendingPathComponent("models/joytag")

        try FileManager.default.createDirectory(at: joytagDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: modelsJoytagDir, withIntermediateDirectories: true)

        try Data("dummy".utf8).write(to: joytagDir.appendingPathComponent("model.onnx"))
        try Data("dummy".utf8).write(to: modelsJoytagDir.appendingPathComponent("model.onnx"))

        XCTAssertTrue(FileManager.default.fileExists(atPath: joytagDir.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: modelsJoytagDir.path))

        LocalAIStore.cleanupLegacyJoyTag(in: tempDir)

        XCTAssertFalse(FileManager.default.fileExists(atPath: joytagDir.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: modelsJoytagDir.path))

        try? FileManager.default.removeItem(at: tempDir)
    }

    func testLocalAIEngineAppleVisionSuggestsTags() async throws {
        let image = NSImage(size: NSSize(width: 64, height: 64))
        image.lockFocus()
        NSColor.blue.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 64, height: 64)).fill()
        image.unlockFocus()
        let tiff = image.tiffRepresentation
        let rep = tiff.flatMap { NSBitmapImageRep(data: $0) }
        let jpegData = try XCTUnwrap(rep?.representation(using: .jpeg, properties: [.compressionFactor: 0.8]))

        let result = try await LocalAIEngine.shared.suggest(
            scheme: .appleVision,
            frames: [jpegData],
            catalog: TagCatalog.bundled
        )

        XCTAssertEqual(result["provider"] as? String, AIProvider.appleVision.rawValue)
        XCTAssertEqual(result["model"] as? String, LocalAIScheme.appleVision.rawValue)
        let tags = result["tags"] as? [[String: String]]
        let keywords = result["keywords"] as? [String]
        XCTAssertNotNil(tags)
        XCTAssertNotNil(keywords)
        XCTAssertTrue(tags?.contains(where: { $0["category"] == "people" }) == true)
        XCTAssertTrue(keywords?.contains("no people") == true)
    }

    func testLocalAIEngineEmptyFramesThrows() async {
        do {
            _ = try await LocalAIEngine.shared.suggest(
                scheme: .appleVision,
                frames: [],
                catalog: TagCatalog.bundled
            )
            XCTFail("Expected missingFrames error")
        } catch let error as AITagError {
            if case .missingFrames = error {
                // Expected
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testLocalAIEngineUninstalledSchemeThrowsNotReady() async {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("rolltag-uninstalled-test-\(UUID().uuidString)")
        LocalAIStore.customHome = tempDir
        defer {
            LocalAIStore.customHome = nil
            try? FileManager.default.removeItem(at: tempDir)
        }
        let dummyFrame = Data([0xFF, 0xD8, 0xFF, 0xE0])

        do {
            _ = try await LocalAIEngine.shared.suggest(
                scheme: .florence2Base,
                frames: [dummyFrame],
                catalog: TagCatalog.bundled
            )
            XCTFail("Expected florence2_not_ready error when weights are missing")
        } catch let error as AITagError {
            if case .requestFailed(let reason) = error {
                XCTAssertEqual(reason, "florence2_not_ready")
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        do {
            _ = try await LocalAIEngine.shared.suggest(
                scheme: .ramPlus,
                frames: [dummyFrame],
                catalog: TagCatalog.bundled
            )
            XCTFail("Expected ram_plus_not_ready error when weights are missing")
        } catch let error as AITagError {
            if case .requestFailed(let reason) = error {
                XCTAssertEqual(reason, "ram_plus_not_ready")
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testLocalAIEngineFlorence2BaseAndRAMPlusSuggestTagsWhenInstalled() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("rolltag-installed-test-\(UUID().uuidString)")
        LocalAIStore.customHome = tempDir
        defer {
            LocalAIStore.customHome = nil
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create dummy model weights (> 1MB)
        let f2Dir = tempDir.appendingPathComponent("models/florence2")
        let ramDir = tempDir.appendingPathComponent("models/ram_plus")
        try FileManager.default.createDirectory(at: f2Dir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: ramDir, withIntermediateDirectories: true)
        let dummyData = Data(repeating: 0xAA, count: 1_200_000)
        try dummyData.write(to: f2Dir.appendingPathComponent("model.onnx"))
        try dummyData.write(to: ramDir.appendingPathComponent("model.onnx"))

        XCTAssertTrue(LocalAIStore.isInstalled(scheme: .florence2Base))
        XCTAssertTrue(LocalAIStore.isInstalled(scheme: .ramPlus))

        // Create a test frame
        let image = NSImage(size: NSSize(width: 64, height: 64))
        image.lockFocus()
        NSColor.red.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 64, height: 64)).fill()
        image.unlockFocus()
        let tiff = image.tiffRepresentation
        let rep = tiff.flatMap { NSBitmapImageRep(data: $0) }
        let jpegData = try XCTUnwrap(rep?.representation(using: .jpeg, properties: [.compressionFactor: 0.8]))

        // Florence-2 Base
        let f2Result = try await LocalAIEngine.shared.suggest(
            scheme: .florence2Base,
            frames: [jpegData],
            catalog: TagCatalog.bundled
        )
        XCTAssertEqual(f2Result["provider"] as? String, AIProvider.florence2Base.rawValue)
        XCTAssertEqual(f2Result["model"] as? String, LocalAIScheme.florence2Base.rawValue)
        let f2Tags = f2Result["tags"] as? [[String: String]]
        let f2Keywords = f2Result["keywords"] as? [String]
        XCTAssertNotNil(f2Tags)
        XCTAssertNotNil(f2Keywords)
        XCTAssertTrue(f2Tags?.contains(where: { $0["category"] == "people" }) == true)
        XCTAssertTrue(f2Keywords?.contains("no people") == true)

        // RAM++
        let ramResult = try await LocalAIEngine.shared.suggest(
            scheme: .ramPlus,
            frames: [jpegData],
            catalog: TagCatalog.bundled
        )
        XCTAssertEqual(ramResult["provider"] as? String, AIProvider.ramPlus.rawValue)
        XCTAssertEqual(ramResult["model"] as? String, LocalAIScheme.ramPlus.rawValue)
        let ramTags = ramResult["tags"] as? [[String: String]]
        let ramKeywords = ramResult["keywords"] as? [String]
        XCTAssertNotNil(ramTags)
        XCTAssertNotNil(ramKeywords)
        XCTAssertTrue(ramTags?.contains(where: { $0["category"] == "people" }) == true)
        XCTAssertTrue(ramKeywords?.contains("no people") == true)
    }

    func testPortraitPhotoDoesNotGetDistantOrWideTag() async throws {
        let photoPath = "/Volumes/Finland/Finland/March_07_08_Taipei_ICN_Helsinki/ZVE10II/100MSDCF/DSC00264.HIF"
        guard FileManager.default.fileExists(atPath: photoPath) else {
            // Optional integration test if external volume is mounted
            return
        }
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: photoPath) as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let jpegData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
            return
        }

        // Test Apple Vision on portrait photo
        let result = try await LocalAIEngine.shared.suggest(
            scheme: .appleVision,
            frames: [jpegData],
            catalog: TagCatalog.bundled
        )
        let tags = try XCTUnwrap(result["tags"] as? [[String: String]])
        let keywords = try XCTUnwrap(result["keywords"] as? [String])

        // Verify it identifies person and portrait framing, NOT distant/wide
        XCTAssertTrue(tags.contains(where: { $0["category"] == "people" && $0["value"] == "one" }))
        XCTAssertTrue(tags.contains(where: { $0["category"] == "people" && $0["value"] == "adult" }))
        XCTAssertTrue(tags.contains(where: { $0["category"] == "people" && $0["value"] == "portrait" }))
        XCTAssertFalse(tags.contains(where: { $0["category"] == "people" && $0["value"] == "distant" }))
        XCTAssertFalse(tags.contains(where: { $0["category"] == "shot" && $0["value"] == "wide" }))

        // Verify rich tags and keywords
        XCTAssertGreaterThanOrEqual(tags.count, 6)
        XCTAssertGreaterThanOrEqual(keywords.count, 12)

        print("=== Apple Vision Tags: \(tags.map { "\($0["category"] ?? "")/\($0["value"] ?? "")" })")
        print("=== Apple Vision Keywords: \(keywords)")

        if LocalAIStore.isInstalled(scheme: .florence2Base) {
            let f2Result = try await LocalAIEngine.shared.suggest(
                scheme: .florence2Base,
                frames: [jpegData],
                catalog: TagCatalog.bundled
            )
            let f2Tags = try XCTUnwrap(f2Result["tags"] as? [[String: String]])
            let f2Keywords = try XCTUnwrap(f2Result["keywords"] as? [String])
            print("=== Florence-2 Tags: \(f2Tags.map { "\($0["category"] ?? "")/\($0["value"] ?? "")" })")
            print("=== Florence-2 Keywords: \(f2Keywords)")
            XCTAssertGreaterThanOrEqual(f2Tags.count, 6)
            XCTAssertGreaterThanOrEqual(f2Keywords.count, 15)
            XCTAssertTrue(f2Tags.contains(where: { $0["category"] == "people" && $0["value"] == "one" }))
            XCTAssertTrue(f2Tags.contains(where: { $0["category"] == "people" && $0["value"] == "portrait" }))
        }

        if LocalAIStore.isInstalled(scheme: .ramPlus) {
            let ramResult = try await LocalAIEngine.shared.suggest(
                scheme: .ramPlus,
                frames: [jpegData],
                catalog: TagCatalog.bundled
            )
            let ramTags = try XCTUnwrap(ramResult["tags"] as? [[String: String]])
            let ramKeywords = try XCTUnwrap(ramResult["keywords"] as? [String])
            print("=== RAM++ Tags: \(ramTags.map { "\($0["category"] ?? "")/\($0["value"] ?? "")" })")
            print("=== RAM++ Keywords: \(ramKeywords)")
            XCTAssertGreaterThanOrEqual(ramTags.count, 8)
            XCTAssertGreaterThanOrEqual(ramKeywords.count, 20)
            XCTAssertTrue(ramTags.contains(where: { $0["category"] == "people" && $0["value"] == "one" }))
            XCTAssertTrue(ramTags.contains(where: { $0["category"] == "people" && $0["value"] == "portrait" }))
        }
    }

    func testAdultWithSunglassesNotClassifiedAsChildOrDistant() async throws {
        let photoPath = "/Volumes/Finland/Finland/March_10_芬蘭堡/ZVE10II/DCIM/DSC00322.HIF"
        guard FileManager.default.fileExists(atPath: photoPath) else { return }
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: photoPath) as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let jpegData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else { return }

        let result = try await LocalAIEngine.shared.suggest(
            scheme: .appleVision,
            frames: [jpegData],
            catalog: TagCatalog.bundled
        )
        let tags = try XCTUnwrap(result["tags"] as? [[String: String]])
        let keywords = try XCTUnwrap(result["keywords"] as? [String])

        print("=== DSC00322 Tags: \(tags.map { "\($0["category"] ?? "")/\($0["value"] ?? "")" })")
        print("=== DSC00322 Keywords: \(keywords)")

        // Must be adult, NOT child
        XCTAssertTrue(tags.contains(where: { $0["category"] == "people" && $0["value"] == "adult" }))
        XCTAssertFalse(tags.contains(where: { $0["category"] == "people" && $0["value"] == "child" }))

        // Must be portrait / waistUp, NOT distant / wide
        XCTAssertTrue(tags.contains(where: { $0["category"] == "people" && $0["value"] == "portrait" }))
        XCTAssertFalse(tags.contains(where: { $0["category"] == "people" && $0["value"] == "distant" }))

        // Keywords should have sunglasses and beanie, and NOT raw "optical equipment"
        XCTAssertFalse(keywords.contains("optical equipment"))
        XCTAssertTrue(keywords.contains("sunglasses") || keywords.contains("eyewear"))
        XCTAssertTrue(keywords.contains("beanie") || keywords.contains("knit hat"))
    }

    func testPersonStandingInSnowNotClassifiedAsNoPeople() async throws {
        let photoPath = "/Volumes/Finland/Finland/March_09_Helsinka/ZVE10II/100MSDCF/DSC00288.HIF"
        guard FileManager.default.fileExists(atPath: photoPath) else { return }
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: photoPath) as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let jpegData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else { return }

        // Test VisionFrameAnalyzer.observe
        let observation = await VisionFrameAnalyzer.observe(frames: [jpegData])
        XCTAssertEqual(observation.people, "one")
        XCTAssertEqual(observation.peopleCount, 1)

        // Test LocalAIEngine.suggest
        let result = try await LocalAIEngine.shared.suggest(
            scheme: .appleVision,
            frames: [jpegData],
            catalog: TagCatalog.bundled
        )
        let tags = try XCTUnwrap(result["tags"] as? [[String: String]])
        let keywords = try XCTUnwrap(result["keywords"] as? [String])

        print("=== DSC00288 Tags: \(tags.map { "\($0["category"] ?? "")/\($0["value"] ?? "")" })")
        print("=== DSC00288 Keywords: \(keywords)")

        // Must detect one person and adult, NOT no people
        XCTAssertTrue(tags.contains(where: { $0["category"] == "people" && $0["value"] == "one" }))
        XCTAssertFalse(tags.contains(where: { $0["category"] == "people" && $0["value"] == "none" }))
        XCTAssertTrue(tags.contains(where: { $0["category"] == "people" && $0["value"] == "adult" }))
        XCTAssertFalse(keywords.contains("no people"))
        XCTAssertTrue(keywords.contains("one person"))
    }
}
