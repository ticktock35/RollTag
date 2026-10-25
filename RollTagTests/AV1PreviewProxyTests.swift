import XCTest
@testable import RollTag

final class AV1PreviewProxyTests: XCTestCase {
    private var tempURLs: [URL] = []

    override func tearDown() {
        AV1PreviewProxy.automaticallyStartsJobs = true
        for url in tempURLs {
            try? FileManager.default.removeItem(at: url)
        }
        tempURLs.removeAll()
        super.tearDown()
    }

    func testSniffFindsAV1BeforeOtherCodecs() {
        XCTAssertEqual(MatroskaSniff.videoCodec(in: Data("xxxxV_AV1yyyy".utf8)), .av1)
        XCTAssertEqual(MatroskaSniff.videoCodec(in: Data("V_VP9".utf8)), .vp9)
        XCTAssertEqual(MatroskaSniff.videoCodec(in: Data("V_VP8".utf8)), .vp8)
        XCTAssertEqual(MatroskaSniff.videoCodec(in: Data("V_MPEG4/ISO/AVC".utf8)), .other)
    }

    func testNeedsProxyOnlyForAV1WebMAndMKV() throws {
        let av1 = try writeTemp(ext: "webm", payload: Data("V_AV1".utf8))
        let vp9 = try writeTemp(ext: "mkv", payload: Data("V_VP9".utf8))
        let mov = try writeTemp(ext: "mov", payload: Data("V_AV1".utf8))
        XCTAssertTrue(AV1PreviewProxy.needsProxy(for: av1))
        XCTAssertFalse(AV1PreviewProxy.needsProxy(for: vp9))
        XCTAssertFalse(AV1PreviewProxy.needsProxy(for: mov))
    }

    func testArgumentsUseVideoToolboxAndFragmentedMP4() throws {
        let source = URL(fileURLWithPath: "/tmp/clip.webm")
        let output = URL(fileURLWithPath: "/tmp/clip-preview.mp4")
        let args = AV1PreviewProxy.arguments(source: source, output: output)
        XCTAssertTrue(args.contains("h264_videotoolbox"))
        XCTAssertTrue(args.contains("frag_keyframe+empty_moov+default_base_moof"))
        XCTAssertEqual(args[args.firstIndex(of: "-i")! + 1], source.path)
        XCTAssertEqual(args.last, output.path)
    }

    func testFFmpegURLAcceptsAnExecutableCandidate() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rolltag-ffmpeg-\(UUID().uuidString)")
        try Data("#!/bin/sh\n".utf8).write(to: url)
        tempURLs.append(url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        XCTAssertEqual(AV1PreviewProxy.ffmpegURL(candidates: [url.path]), url)
        XCTAssertNil(AV1PreviewProxy.ffmpegURL(candidates: ["/tmp/rolltag-missing-ffmpeg-\(UUID().uuidString)"]))
    }

    func testParsesFFmpegDurationAndTime() {
        let line = "  Duration: 00:12:41.07, start: 0.000000, bitrate: 5789 kb/s"
        let parsed = AV1PreviewLog.parse(line: line)
        XCTAssertEqual(parsed.duration ?? 0, 761.07, accuracy: 0.001)
        XCTAssertNil(parsed.encoded)
        let progress = "frame=  60 fps=39 q=-0.0 Lsize= 964KiB time=00:00:01.96 bitrate=4009.6kbits/s"
        let encoded = AV1PreviewLog.parse(line: progress).encoded ?? 0
        XCTAssertEqual(encoded, 1.96, accuracy: 0.001)
    }

    @MainActor
    func testPresentAV1UsesProxyInsteadOfWebKit() throws {
        AV1PreviewProxy.automaticallyStartsJobs = false
        let url = try writeTemp(ext: "webm", payload: Data("ebmlV_AV1A_OPUS".utf8))
        let playback = PreviewPlayback()
        playback.present(
            PreviewMedia(
                id: UUID(),
                url: url,
                kind: .video,
                filename: url.lastPathComponent,
                width: 3840,
                height: 2160,
                duration: 761,
                fileSize: 16_384
            )
        )
        XCTAssertTrue(playback.usesPlaybackProxy)
        XCTAssertFalse(playback.usesWebKitPlayback)
        XCTAssertTrue(playback.canPlay)
        XCTAssertTrue(playback.isWaitingOnProxy)
        XCTAssertFalse(playback.didFailToLoad)
        XCTAssertNil(playback.player.currentItem)
        playback.unload()
    }

    private func writeTemp(ext: String, payload: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rolltag-av1-\(UUID().uuidString).\(ext)")
        var data = Data(repeating: 0, count: 16_384)
        data.replaceSubrange(0..<payload.count, with: payload)
        try data.write(to: url)
        tempURLs.append(url)
        return url
    }
}
