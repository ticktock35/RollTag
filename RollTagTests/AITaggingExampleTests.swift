import XCTest
@testable import RollTag

final class AITaggingExampleTests: XCTestCase {
    func testMakeKeepsAISourceAndIgnoresEmptyKept() {
        let proposed = [
            TagAssignment.ai(category: "nature", value: "ocean"),
            TagAssignment.path(category: "place", value: "malaysia"),
        ]
        XCTAssertNil(AITaggingExample.make(ai: proposed, kept: []))
        let example = AITaggingExample.make(
            ai: proposed,
            kept: [TagAssignment.user(category: "nature", value: "lake")]
        )
        XCTAssertEqual(example?.ai.map(\.value), ["ocean"])
        XCTAssertEqual(example?.kept.map(\.value), ["lake"])
        XCTAssertTrue(example?.isCorrection == true)
    }

    func testRecordingPrefersCorrectionsAndCaps() {
        let accepted = AITaggingExample(
            ai: [AITagRef(category: "mood", value: "calm")],
            kept: [AITagRef(category: "mood", value: "calm")]
        )
        let correction = AITaggingExample(
            ai: [AITagRef(category: "nature", value: "ocean")],
            kept: [AITagRef(category: "nature", value: "lake")]
        )
        var stored: [AITaggingExample] = []
        for index in 0..<10 {
            stored = AITaggingExample.recording(
                stored,
                inserting: [
                    AITaggingExample(
                        ai: [AITagRef(category: "shot", value: "wide")],
                        kept: [AITagRef(category: "shot", value: "wide\(index)")]
                    )
                ]
            )
        }
        XCTAssertEqual(stored.count, 8)
        XCTAssertEqual(stored.first?.kept.first?.value, "wide9")

        let next = AITaggingExample.recording([accepted], inserting: [accepted, correction])
        XCTAssertEqual(next.first, correction)
        XCTAssertEqual(next.dropFirst().first, accepted)
    }
}
