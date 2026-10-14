import AppKit
import XCTest
@testable import RollTag

final class JoyTagTests: XCTestCase {
    func testKeywordsReplaceUnderscoresAndKeepGettyShape() {
        XCTAssertEqual(JoyTagTags.displayKeyword("blue_sky"), "blue sky")
        XCTAssertEqual(JoyTagTags.displayKeyword("ocean"), "ocean")
        XCTAssertNil(JoyTagTags.displayKeyword("ab"))
        XCTAssertNil(JoyTagTags.displayKeyword("rating:safe"))
    }

    func testKeywordsSortByScoreAndCap() {
        let tags = ["solo", "blue_sky", "ocean", "1girl", "forest", "outdoors"]
        let scores: [Float] = [0.2, 0.91, 0.88, 0.5, 0.7, 0.35]
        XCTAssertEqual(
            JoyTagTags.keywords(tags: tags, scores: scores, threshold: 0.4, limit: 3),
            ["blue sky", "ocean", "forest"]
        )
    }

    func testProbabilitiesLeaveUnitIntervalAlone() {
        XCTAssertEqual(JoyTagEngine.probabilities([0.1, 0.4, 1.0]), [0.1, 0.4, 1.0])
        let logits = JoyTagEngine.probabilities([-2, 0, 2])
        XCTAssertEqual(logits[1], 0.5, accuracy: 0.0001)
        XCTAssertGreaterThan(logits[2], 0.8)
        XCTAssertLessThan(logits[0], 0.2)
    }

    func testPreprocessorWritesNCHWFloats() throws {
        let tensor = try JoyTagImage.nchwTensor(from: solidJPEG(width: 32, height: 48), size: 8)
        XCTAssertEqual(tensor.count, 3 * 8 * 8 * MemoryLayout<Float>.size)
        let values = tensor.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        XCTAssertEqual(values.count, 192)
        XCTAssertTrue(values.allSatisfy { $0.isFinite })
    }

    private func solidJPEG(width: Int, height: Int) -> Data {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.red.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
        image.unlockFocus()
        let tiff = image.tiffRepresentation
        let rep = tiff.flatMap { NSBitmapImageRep(data: $0) }
        return rep?.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) ?? Data()
    }
}
