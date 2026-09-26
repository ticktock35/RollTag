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

    func testFormatsTenthsForTrim() {
        XCTAssertEqual(PlaybackClock.formatPrecise(0), "00:00.0")
        XCTAssertEqual(PlaybackClock.formatPrecise(5.2), "00:05.2")
        XCTAssertEqual(PlaybackClock.formatPrecise(75.9), "01:15.9")
        XCTAssertEqual(PlaybackClock.formatPrecise(3661.4), "1:01:01.4")
        XCTAssertEqual(PlaybackClock.formatPrecise(-1), "00:00.0")
    }

    @MainActor
    func testPresentVideoAttachesPlayerItem() {
        let playback = PreviewPlayback()
        playback.present(
            PreviewMedia(
                id: UUID(),
                url: URL(fileURLWithPath: "/tmp/clip.mov"),
                kind: .video,
                filename: "clip.mov",
                width: 3840,
                height: 2160,
                duration: 8,
                fileSize: 5_000_000
            )
        )
        XCTAssertNotNil(playback.player.currentItem)
        XCTAssertTrue(playback.isItemLoaded)
        XCTAssertEqual(playback.duration, 8)
        XCTAssertTrue(playback.canPlay)
    }

    @MainActor
    func testPresentImageLeavesPlayerEmpty() {
        let playback = PreviewPlayback()
        playback.present(
            PreviewMedia(
                id: UUID(),
                url: URL(fileURLWithPath: "/tmp/still.jpg"),
                kind: .image,
                filename: "still.jpg",
                width: 2048,
                height: 1365,
                duration: nil,
                fileSize: 320_000
            )
        )
        XCTAssertNil(playback.player.currentItem)
        XCTAssertFalse(playback.isItemLoaded)
        XCTAssertFalse(playback.canPlay)
    }
}
