import AppKit
import AVFoundation
import Foundation
import Observation

struct PreviewMedia: Equatable {
    var id: UUID
    var url: URL
    var kind: MediaKind
    var filename: String
    var width: Int?
    var height: Int?
    var duration: Double?
    var fileSize: Int64
}

struct TrimSession: Equatable, Identifiable {
    var footageID: UUID
    var warehouseID: UUID
    var url: URL
    var filename: String

    var id: UUID { footageID }
}

@MainActor
@Observable
final class PreviewPlayback {
    private(set) var player: AVPlayer
    var media: PreviewMedia?
    var isPlaying = false
    var isFullscreen = false
    var currentSeconds = 0.0
    var duration = 0.0
    var isScrubbing = false
    var didFailToLoad = false
    var isIncompleteFile = false

    private var loadedURL: URL?
    private var presentGeneration = 0
    private var endObserver: NSObjectProtocol?
    private var timeObserver: Any?
    private var itemStatusObservation: NSKeyValueObservation?
    private var enteredSystemFullscreen = false
    private var resumeAfterScrub = false

    init() {
        player = Self.makePlayer()
    }

    var isItemLoaded: Bool { loadedURL != nil && player.currentItem != nil }

    var canPlay: Bool {
        guard let media, !isIncompleteFile, !didFailToLoad else { return false }
        return media.kind == .video || media.kind == .audio
    }

    func present(_ next: PreviewMedia?) {
        media = next
        presentGeneration += 1
        detachPlayer()
        currentSeconds = 0
        didFailToLoad = false
        guard let next else {
            duration = 0
            isIncompleteFile = false
            return
        }
        duration = next.duration ?? 0
        if next.kind == .video, next.fileSize < MediaConstants.minimumPlayableVideoBytes {
            isIncompleteFile = true
            return
        }
        isIncompleteFile = false
        if next.kind == .video || next.kind == .audio {
            ensureItemLoaded()
        }
    }

    func play() {
        guard canPlay, !isPlaying else { return }
        ensureItemLoaded()
        player.play()
        isPlaying = true
    }

    func togglePlayPause() {
        guard canPlay else { return }
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func beginScrubbing() {
        guard canPlay else { return }
        ensureItemLoaded()
        isScrubbing = true
        resumeAfterScrub = isPlaying
        if isPlaying {
            player.pause()
            isPlaying = false
        }
    }

    func scrub(to seconds: Double) {
        guard canPlay else { return }
        let clamped = clampedTime(seconds)
        currentSeconds = clamped
        seek(to: clamped, precise: false)
    }

    func endScrubbing() {
        guard isScrubbing else { return }
        isScrubbing = false
        seek(to: currentSeconds, precise: true)
        if resumeAfterScrub {
            player.play()
            isPlaying = true
        }
        resumeAfterScrub = false
    }

    func toggleFullscreen() {
        if isFullscreen {
            exitFullscreen()
        } else {
            enterFullscreen()
        }
    }

    func enterFullscreen() {
        guard media != nil else { return }
        isFullscreen = true
        if let window = NSApp.keyWindow, !window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
            enteredSystemFullscreen = true
        }
    }

    func exitFullscreen() {
        isFullscreen = false
        if enteredSystemFullscreen, let window = NSApp.keyWindow, window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
        enteredSystemFullscreen = false
    }

    func noteSystemExitedFullscreen() {
        isFullscreen = false
        enteredSystemFullscreen = false
    }

    func unload() {
        presentGeneration += 1
        media = nil
        detachPlayer()
        duration = 0
        currentSeconds = 0
        isIncompleteFile = false
        didFailToLoad = false
        exitFullscreen()
    }

    private func ensureItemLoaded() {
        guard let media, canPlay else { return }
        if loadedURL == media.url, player.currentItem != nil { return }
        replaceCurrentItem(url: media.url)
    }

    private func replaceCurrentItem(url: URL) {
        pause()
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        loadedURL = url
        duration = media?.duration ?? 0
        currentSeconds = 0
        didFailToLoad = false
        isIncompleteFile = false
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
        let item = AVPlayerItem(asset: asset)
        observeItem(item)
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.player.seek(to: .zero)
                self?.isPlaying = false
                self?.currentSeconds = 0
            }
        }
        player.replaceCurrentItem(with: item)
        ensureTimeObserver()
    }

    private func detachPlayer() {
        pause()
        isScrubbing = false
        resumeAfterScrub = false
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        itemStatusObservation = nil
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        let hadItem = loadedURL != nil || player.currentItem != nil
        loadedURL = nil
        player.currentItem?.asset.cancelLoading()
        player.replaceCurrentItem(with: nil)
        if hadItem {
            player = Self.makePlayer()
        }
    }

    private static func makePlayer() -> AVPlayer {
        let player = AVPlayer()
        player.automaticallyWaitsToMinimizeStalling = false
        return player
    }

    private func ensureTimeObserver() {
        guard timeObserver == nil else { return }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1.0 / 15.0, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                self?.notePlayerTime(time)
            }
        }
    }

    private func observeItem(_ item: AVPlayerItem) {
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                switch item.status {
                case .readyToPlay:
                    self?.didFailToLoad = false
                    self?.noteDuration(item.duration.seconds)
                case .failed:
                    self?.didFailToLoad = true
                default:
                    break
                }
            }
        }
    }

    private func notePlayerTime(_ time: CMTime) {
        guard !isScrubbing else { return }
        let seconds = time.seconds
        guard seconds.isFinite else { return }
        currentSeconds = clampedTime(seconds)
        if duration <= 0, let itemDuration = player.currentItem?.duration.seconds, itemDuration.isFinite, itemDuration > 0 {
            duration = itemDuration
        }
    }

    private func noteDuration(_ seconds: Double) {
        guard seconds.isFinite, seconds > 0 else { return }
        duration = seconds
    }

    private func seek(to seconds: Double, precise: Bool) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        if precise {
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        } else {
            let slop = CMTime(seconds: 0.12, preferredTimescale: 600)
            player.seek(to: time, toleranceBefore: slop, toleranceAfter: slop)
        }
    }

    private func clampedTime(_ seconds: Double) -> Double {
        let upper = duration > 0 ? duration : seconds
        return min(max(0, seconds), upper)
    }
}

enum PlaybackClock {
    static func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }
        let total = Int(seconds.rounded(.towardZero))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remainder = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainder)
        }
        return String(format: "%02d:%02d", minutes, remainder)
    }

    static func formatPrecise(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00.0" }
        let tenths = Int((seconds * 10).rounded(.towardZero))
        let total = tenths / 10
        let tenth = tenths % 10
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remainder = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d.%d", hours, minutes, remainder, tenth)
        }
        return String(format: "%02d:%02d.%d", minutes, remainder, tenth)
    }
}
