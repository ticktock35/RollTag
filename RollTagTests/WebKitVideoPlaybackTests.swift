import XCTest
@testable import RollTag

final class WebKitVideoPlaybackTests: XCTestCase {
    func testSupportsWebMAndMKVOnly() {
        XCTAssertTrue(WebKitVideoPlayback.supports(URL(fileURLWithPath: "/tmp/clip.webm")))
        XCTAssertTrue(WebKitVideoPlayback.supports(URL(fileURLWithPath: "/tmp/clip.mkv")))
        XCTAssertFalse(WebKitVideoPlayback.supports(URL(fileURLWithPath: "/tmp/clip.mov")))
        XCTAssertFalse(WebKitVideoPlayback.supports(URL(fileURLWithPath: "/tmp/clip.mp4")))
    }

    func testEncodedFileNameEscapesBracketsAndRoundTrips() {
        let encoded = WebKitVideoPlayback.encodedFileName("黑海 [gRGZPV9pyng].webm")
        XCTAssertFalse(encoded.contains("["))
        XCTAssertFalse(encoded.contains("]"))
        XCTAssertEqual(encoded.removingPercentEncoding, "黑海 [gRGZPV9pyng].webm")
    }
}
