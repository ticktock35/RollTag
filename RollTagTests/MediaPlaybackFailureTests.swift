import XCTest
@testable import RollTag

final class MediaPlaybackFailureTests: XCTestCase {
    func testMissingFileIsNotADecodeFailure() {
        XCTAssertEqual(
            MediaPlaybackFailure.classify(exists: false, fileSize: 3_381_977_535, kind: .video),
            .missing
        )
    }

    func testTinyVideoIsIncomplete() {
        XCTAssertEqual(
            MediaPlaybackFailure.classify(exists: true, fileSize: 200, kind: .video),
            .incomplete
        )
    }

    func testExistingVideoWithNoErrorIsPlayable() {
        XCTAssertEqual(
            MediaPlaybackFailure.classify(exists: true, fileSize: 3_381_977_535, kind: .video),
            .none
        )
    }

    func testPlayerFileNotFoundErrorIsMissing() {
        let error = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)
        XCTAssertEqual(
            MediaPlaybackFailure.classify(exists: true, fileSize: 1_000_000, kind: .video, playerError: error),
            .missing
        )
    }

    func testOtherPlayerErrorIsDecode() {
        let error = NSError(domain: NSOSStatusErrorDomain, code: -12939)
        XCTAssertEqual(
            MediaPlaybackFailure.classify(exists: true, fileSize: 1_000_000, kind: .video, playerError: error),
            .decode
        )
    }
}
