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
        XCTAssertEqual(playback.zoomScale, 1)
        XCTAssertFalse(playback.showsDecodedVideoFrame)
        playback.play()
        XCTAssertTrue(playback.showsDecodedVideoFrame)
        playback.pause()
        XCTAssertFalse(playback.showsDecodedVideoFrame)
        playback.scrub(to: 1.2)
        XCTAssertTrue(playback.showsDecodedVideoFrame)
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

    @MainActor
    func testZoomClampsAndResetReturnsToFit() {
        let playback = PreviewPlayback()
        playback.setZoom(0.2)
        XCTAssertEqual(playback.zoomScale, 1)
        playback.setZoom(12)
        XCTAssertEqual(playback.zoomScale, 8)
        playback.zoomOffset = CGSize(width: 40, height: -20)
        playback.resetZoom()
        XCTAssertEqual(playback.zoomScale, 1)
        XCTAssertEqual(playback.zoomOffset, .zero)
        playback.setZoom(3)
        playback.zoomOffset = CGSize(width: 400, height: 400)
        playback.clampOffset(in: CGSize(width: 200, height: 100))
        XCTAssertLessThanOrEqual(abs(playback.zoomOffset.width), 200)
        XCTAssertLessThanOrEqual(abs(playback.zoomOffset.height), 100)
        playback.present(nil)
        XCTAssertEqual(playback.zoomScale, 1)
        XCTAssertEqual(playback.zoomOffset, .zero)
    }

    @MainActor
    func testSkipMovesFiveSecondsAndClamps() {
        let playback = PreviewPlayback()
        playback.present(
            PreviewMedia(
                id: UUID(),
                url: URL(fileURLWithPath: "/tmp/clip.mov"),
                kind: .video,
                filename: "clip.mov",
                width: 1920,
                height: 1080,
                duration: 12,
                fileSize: 5_000_000
            )
        )
        playback.skip(by: PreviewPlayback.skipSeconds)
        XCTAssertEqual(playback.currentSeconds, 5, accuracy: 0.01)
        playback.skip(by: PreviewPlayback.skipSeconds)
        XCTAssertEqual(playback.currentSeconds, 10, accuracy: 0.01)
        playback.skip(by: PreviewPlayback.skipSeconds)
        XCTAssertEqual(playback.currentSeconds, 12, accuracy: 0.01)
        playback.skip(by: -PreviewPlayback.skipSeconds)
        XCTAssertEqual(playback.currentSeconds, 7, accuracy: 0.01)
        playback.skip(by: -20)
        XCTAssertEqual(playback.currentSeconds, 0, accuracy: 0.01)
    }

    @MainActor
    func testPresentSameClipKeepsCurrentTime() {
        let playback = PreviewPlayback()
        let media = PreviewMedia(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/clip.mov"),
            kind: .video,
            filename: "clip.mov",
            width: 1920,
            height: 1080,
            duration: 120,
            fileSize: 5_000_000
        )
        playback.present(media)
        playback.skip(by: 75)
        XCTAssertEqual(playback.currentSeconds, 75, accuracy: 0.01)
        playback.present(media)
        XCTAssertEqual(playback.currentSeconds, 75, accuracy: 0.01)
        XCTAssertTrue(playback.isItemLoaded)
    }

    @MainActor
    func testFullscreenTransitionPausesThenResumesFromSameTime() {
        let playback = PreviewPlayback()
        playback.present(
            PreviewMedia(
                id: UUID(),
                url: URL(fileURLWithPath: "/tmp/clip.mov"),
                kind: .video,
                filename: "clip.mov",
                width: 1920,
                height: 1080,
                duration: 120,
                fileSize: 5_000_000
            )
        )
        playback.skip(by: 75)
        playback.play()
        playback.beginFullscreenTransition()
        XCTAssertFalse(playback.isPlaying)
        XCTAssertEqual(playback.currentSeconds, 75, accuracy: 0.01)
        playback.finishFullscreenTransition()
        XCTAssertEqual(playback.currentSeconds, 75, accuracy: 0.01)
        XCTAssertTrue(playback.isPlaying)
    }

    @MainActor
    func testHoldSpeedOnlyWhilePlaying() {
        let playback = PreviewPlayback()
        playback.present(
            PreviewMedia(
                id: UUID(),
                url: URL(fileURLWithPath: "/tmp/clip.mov"),
                kind: .video,
                filename: "clip.mov",
                width: 1920,
                height: 1080,
                duration: 12,
                fileSize: 5_000_000
            )
        )
        playback.beginHoldSpeed()
        XCTAssertFalse(playback.isHoldSpeed)
        XCTAssertEqual(playback.player.rate, 0)
        playback.play()
        playback.beginHoldSpeed()
        XCTAssertTrue(playback.isHoldSpeed)
        XCTAssertEqual(playback.player.rate, PreviewPlayback.holdRate)
        playback.endHoldSpeed()
        XCTAssertFalse(playback.isHoldSpeed)
        XCTAssertEqual(playback.player.rate, 1)
        playback.beginHoldSpeed()
        playback.pause()
        XCTAssertFalse(playback.isHoldSpeed)
        XCTAssertEqual(playback.player.rate, 0)
    }

    func testTwoFingerPanDefaultFollowsFingersAndInvertFlipsBothAxes() {
        let follow = MediaPan.twoFingerDelta(x: 4, y: -3, invert: false)
        XCTAssertEqual(follow.width, -4)
        XCTAssertEqual(follow.height, -3)
        let inverted = MediaPan.twoFingerDelta(x: 4, y: -3, invert: true)
        XCTAssertEqual(inverted.width, 4)
        XCTAssertEqual(inverted.height, 3)
    }
}
