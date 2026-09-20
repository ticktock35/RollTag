import XCTest
@testable import RollTag

final class PlaybackClockTests: XCTestCase {
    func testFormatsMinutesAndSeconds() {
        XCTAssertEqual(PlaybackClock.format(0), "00:00")
        XCTAssertEqual(PlaybackClock.format(5), "00:05")
        XCTAssertEqual(PlaybackClock.format(75), "01:15")
    }

    func testFormatsHours() {
        XCTAssertEqual(PlaybackClock.format(3661), "1:01:01")
    }

    func testRejectsInvalidValues() {
        XCTAssertEqual(PlaybackClock.format(-3), "00:00")
        XCTAssertEqual(PlaybackClock.format(.nan), "00:00")
    }
}
