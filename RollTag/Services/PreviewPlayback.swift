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
    var isSourceMissing = false
    var isPreparingProxy = false
    var pendingWebKitSeek: Double?
    var zoomScale: CGFloat = 1
    var zoomOffset: CGSize = .zero
    private(set) var isHoldSpeed = false

    static let skipSeconds = 5.0
    static let holdRate: Float = 2

    private var loadedURL: URL?
    private var presentGeneration = 0
    private var endObserver: NSObjectProtocol?
    private var timeObserver: Any?
    private var itemStatusObservation: NSKeyValueObservation?
    private var enteredSystemFullscreen = false
    private var resumeAfterScrub = false
    private var awaitingSystemFullscreenEnter = false
    private var hasPendingFullscreenResume = false
    private var fullscreenResumePlaying = false
    private var fullscreenResumeSeconds = 0.0
    private var fullscreenResumeTask: Task<Void, Never>?
    private var proxyJob: AV1PreviewJob?
    private var pendingProxySeek: Double?
    private var proxyResumeAt: Double?
    private var proxyReloadPending = false
    private var proxyLoadedDuration = 0.0

    init() {
        player = Self.makePlayer()
    }

    var isItemLoaded: Bool {
        if usesWebKitPlayback { return media != nil && !isSourceMissing }
        return loadedURL != nil && player.currentItem != nil
    }

    var usesPlaybackProxy: Bool {
        guard let media, media.kind == .video, !isSourceMissing, !isIncompleteFile else { return false }
        return AV1PreviewProxy.needsProxy(for: media.url)
    }

    var isWaitingOnProxy: Bool {
        isPreparingProxy || pendingProxySeek != nil
    }

    var usesWebKitPlayback: Bool {
        guard let media, media.kind == .video, !isSourceMissing, !isIncompleteFile else { return false }
        guard !usesPlaybackProxy else { return false }
        return WebKitVideoPlayback.supports(media.url)
    }

    /// Paused on the first frame: AVPlayer often shows a soft proxy. Use a still from the original instead.
    var showsDecodedVideoFrame: Bool {
        if usesWebKitPlayback { return true }
        return isItemLoaded && (isPlaying || currentSeconds > 0.05)
    }

    var canPlay: Bool {
        guard let media, !isIncompleteFile, !didFailToLoad, !isSourceMissing else { return false }
        return media.kind == .video || media.kind == .audio
    }

    func present(_ next: PreviewMedia?) {
        if let next, media?.id == next.id, media?.url == next.url, media?.kind == next.kind {
            media = next
            if let duration = next.duration, duration > 0 {
                self.duration = duration
            }
            refreshSource(next)
            if canPlay, loadedURL != next.url {
                ensureItemLoaded()
            }
            return
        }
        media = next
        presentGeneration += 1
        detachPlayer()
        currentSeconds = 0
        pendingWebKitSeek = nil
        resetFailure()
        resetZoom()
        guard let next else {
            duration = 0
            return
        }
        duration = next.duration ?? 0
        applyFailure(Self.failure(for: next))
        if canPlay {
            ensureItemLoaded()
        }
    }

    func play() {
        guard canPlay, !isPlaying else { return }
        if usesWebKitPlayback {
            isPlaying = true
            return
        }
        ensureItemLoaded()
        if usesPlaybackProxy, pendingProxySeek != nil {
            isPlaying = true
            return
        }
        player.play()
        player.rate = isHoldSpeed ? Self.holdRate : 1
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
        endHoldSpeed()
        if !usesWebKitPlayback {
            player.pause()
            player.rate = 0
        }
        isPlaying = false
    }

    func skip(by seconds: Double) {
        guard canPlay else { return }
        ensureItemLoaded()
        let next = clampedTime(currentSeconds + seconds)
        currentSeconds = next
        seek(to: next, precise: false)
    }

    func beginHoldSpeed() {
        guard canPlay, isPlaying else { return }
        isHoldSpeed = true
        if usesWebKitPlayback { return }
        ensureItemLoaded()
        player.rate = Self.holdRate
    }

    func endHoldSpeed() {
        guard isHoldSpeed else { return }
        isHoldSpeed = false
        if usesWebKitPlayback { return }
        if isPlaying {
            player.rate = 1
        }
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
            if usesWebKitPlayback {
                isPlaying = true
            } else {
                player.play()
                isPlaying = true
            }
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
        guard media != nil, !isFullscreen else { return }
        beginFullscreenTransition()
        isFullscreen = true
        if let window = NSApp.keyWindow, !window.styleMask.contains(.fullScreen) {
            awaitingSystemFullscreenEnter = true
            enteredSystemFullscreen = true
            window.toggleFullScreen(nil)
            fullscreenResumeTask?.cancel()
            fullscreenResumeTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 800_000_000)
                guard !Task.isCancelled, self.awaitingSystemFullscreenEnter else { return }
                self.awaitingSystemFullscreenEnter = false
                self.finishFullscreenTransition()
            }
        } else {
            finishFullscreenTransition()
        }
    }

    func exitFullscreen() {
        awaitingSystemFullscreenEnter = false
        fullscreenResumeTask?.cancel()
        fullscreenResumeTask = nil
        isFullscreen = false
        if enteredSystemFullscreen, let window = NSApp.keyWindow, window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
        enteredSystemFullscreen = false
    }

    func noteSystemEnteredFullscreen() {
        guard awaitingSystemFullscreenEnter else { return }
        awaitingSystemFullscreenEnter = false
        fullscreenResumeTask?.cancel()
        fullscreenResumeTask = nil
        finishFullscreenTransition()
    }

    func noteSystemExitedFullscreen() {
        awaitingSystemFullscreenEnter = false
        fullscreenResumeTask?.cancel()
        fullscreenResumeTask = nil
        isFullscreen = false
        enteredSystemFullscreen = false
    }

    func beginFullscreenTransition() {
        fullscreenResumePlaying = isPlaying && canPlay
        fullscreenResumeSeconds = snapshotCurrentTime()
        currentSeconds = fullscreenResumeSeconds
        hasPendingFullscreenResume = true
        pause()
    }

    func finishFullscreenTransition() {
        guard hasPendingFullscreenResume else { return }
        hasPendingFullscreenResume = false
        let at = fullscreenResumeSeconds
        let shouldPlay = fullscreenResumePlaying
        fullscreenResumePlaying = false
        currentSeconds = at
        seek(to: at, precise: true)
        if shouldPlay {
            play()
        }
    }

    func unload() {
        presentGeneration += 1
        media = nil
        detachPlayer()
        duration = 0
        currentSeconds = 0
        pendingWebKitSeek = nil
        cancelProxy()
        resetFailure()
        resetZoom()
        exitFullscreen()
    }

    func resetZoom() {
        zoomScale = 1
        zoomOffset = .zero
    }

    func setZoom(_ scale: CGFloat) {
        let next = min(max(scale, Self.minZoom), Self.maxZoom)
        zoomScale = next
        if next <= Self.minZoom + 0.001 {
            zoomOffset = .zero
        }
    }

    func clampOffset(in viewport: CGSize) {
        guard zoomScale > Self.minZoom, viewport.width > 0, viewport.height > 0 else {
            zoomOffset = .zero
            return
        }
        let extraX = max(0, viewport.width * (zoomScale - 1) / 2)
        let extraY = max(0, viewport.height * (zoomScale - 1) / 2)
        zoomOffset.width = min(max(zoomOffset.width, -extraX), extraX)
        zoomOffset.height = min(max(zoomOffset.height, -extraY), extraY)
    }

    private func refreshSource(_ next: PreviewMedia) {
        let failure = Self.failure(for: next)
        let shouldReload = failure == .none && (isSourceMissing || didFailToLoad || isIncompleteFile || loadedURL == nil)
        applyFailure(failure)
        if shouldReload {
            loadedURL = nil
            ensureItemLoaded()
        }
    }

    private static func failure(for media: PreviewMedia) -> MediaPlaybackFailure {
        MediaPlaybackFailure.classify(
            exists: FileManager.default.fileExists(atPath: media.url.path),
            fileSize: media.fileSize,
            kind: media.kind
        )
    }

    private func applyFailure(_ failure: MediaPlaybackFailure) {
        isSourceMissing = failure == .missing
        isIncompleteFile = failure == .incomplete
        didFailToLoad = failure == .decode
    }

    private func resetFailure() {
        applyFailure(.none)
    }

    private static let minZoom: CGFloat = 1
    private static let maxZoom: CGFloat = 8

    func noteWebKitTime(_ seconds: Double, duration: Double) {
        guard usesWebKitPlayback, !isScrubbing else { return }
        if duration.isFinite, duration > 0 {
            self.duration = duration
        }
        if seconds.isFinite {
            currentSeconds = clampedTime(seconds)
        }
    }

    func noteWebKitEnded() {
        guard usesWebKitPlayback else { return }
        isPlaying = false
        isHoldSpeed = false
        currentSeconds = 0
        pendingWebKitSeek = 0
    }

    func noteWebKitFailed() {
        guard usesWebKitPlayback else { return }
        didFailToLoad = true
        isPlaying = false
    }

    private func ensureItemLoaded() {
        guard let media, canPlay, !usesWebKitPlayback else { return }
        if usesPlaybackProxy {
            startProxyIfNeeded()
            return
        }
        if loadedURL == media.url, player.currentItem != nil { return }
        replaceCurrentItem(url: media.url)
    }

    private func startProxyIfNeeded() {
        guard proxyJob == nil, let media else { return }
        guard AV1PreviewProxy.automaticallyStartsJobs else {
            isPreparingProxy = true
            return
        }
        let generation = presentGeneration
        let job = AV1PreviewJob()
        proxyJob = job
        isPreparingProxy = true
        job.start(source: media.url) { [weak self] seconds in
            guard let self, self.presentGeneration == generation, self.duration <= 0 else { return }
            self.duration = seconds
        } onProgress: { [weak self] encoded in
            guard let self, self.presentGeneration == generation else { return }
            let loaded = self.player.currentItem?.duration.seconds ?? 0
            let ahead = !loaded.isFinite || encoded > loaded + 1
            if let pending = self.pendingProxySeek, encoded + 0.3 >= pending, ahead || loaded <= 0 {
                self.refreshProxyItem()
                return
            }
            if ahead, loaded > 1, self.currentSeconds >= loaded - 1.2 {
                self.refreshProxyItem()
            }
        } onPlayable: { [weak self] url in
            guard let self, self.presentGeneration == generation else { return }
            self.replaceCurrentItem(url: url, resetClock: self.player.currentItem == nil)
        } onFinished: { [weak self] _ in
            guard let self, self.presentGeneration == generation else { return }
            let available = self.player.currentItem?.duration.seconds ?? 0
            if available > 1, self.duration > available + 1.5 {
                self.refreshProxyItem()
            } else if let pending = self.pendingProxySeek, available.isFinite, pending <= available + 0.05 {
                self.noteProxyReady()
            }
        } onFailed: { [weak self] in
            guard let self, self.presentGeneration == generation else { return }
            self.proxyJob = nil
            self.isPreparingProxy = false
            self.pendingProxySeek = nil
            if self.player.currentItem == nil {
                self.didFailToLoad = true
            }
        }
    }

    private func refreshProxyItem() {
        guard usesPlaybackProxy, !proxyReloadPending, let url = proxyJob?.outputURL else { return }
        let available = player.currentItem?.duration.seconds ?? 0
        if available.isFinite, proxyLoadedDuration > 0, available <= proxyLoadedDuration + 0.3,
           pendingProxySeek == nil {
            return
        }
        if proxyResumeAt == nil {
            proxyResumeAt = pendingProxySeek ?? currentSeconds
        }
        proxyReloadPending = true
        replaceCurrentItem(url: url, resetClock: false)
    }

    private func cancelProxy() {
        proxyJob?.cancel()
        proxyJob = nil
        pendingProxySeek = nil
        proxyResumeAt = nil
        proxyReloadPending = false
        proxyLoadedDuration = 0
        isPreparingProxy = false
    }

    private func noteProxyReady() {
        guard usesPlaybackProxy else { return }
        isPreparingProxy = false
        proxyReloadPending = false
        let available = player.currentItem?.duration.seconds ?? 0
        if available.isFinite, available > 0 {
            proxyLoadedDuration = available
        }
        let resume = pendingProxySeek ?? proxyResumeAt
        proxyResumeAt = nil
        if let resume, available.isFinite, resume <= available + 0.05 {
            pendingProxySeek = nil
            if resume > 0.05 {
                currentSeconds = resume
                seek(to: resume, precise: true)
            }
        }
        if isPlaying, pendingProxySeek == nil {
            player.play()
            player.rate = isHoldSpeed ? Self.holdRate : 1
        }
    }

    private func replaceCurrentItem(url: URL, resetClock: Bool = true) {
        let keepPlaying = isPlaying
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        player.pause()
        isPlaying = keepPlaying
        loadedURL = url
        if resetClock {
            if pendingProxySeek == nil {
                currentSeconds = 0
            }
            if let known = media?.duration, known > 0 {
                duration = known
            }
        }
        resetFailure()
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
        let item = AVPlayerItem(
            asset: asset,
            automaticallyLoadedAssetKeys: ["playable", "tracks", "duration"]
        )
        item.preferredMaximumResolution = ThumbnailService.previewMaxResolution
        observeItem(item)
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.usesPlaybackProxy, self.proxyJob?.isComplete != true {
                    self.refreshProxyItem()
                    return
                }
                self.pause()
                self.player.seek(to: .zero)
                self.currentSeconds = 0
            }
        }
        player.replaceCurrentItem(with: item)
        ensureTimeObserver()
    }

    private func detachPlayer() {
        cancelProxy()
        awaitingSystemFullscreenEnter = false
        hasPendingFullscreenResume = false
        fullscreenResumePlaying = false
        fullscreenResumeTask?.cancel()
        fullscreenResumeTask = nil
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
        player.automaticallyWaitsToMinimizeStalling = true
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
                    self?.resetFailure()
                    self?.noteDuration(item.duration.seconds)
                    self?.noteProxyReady()
                case .failed:
                    let path = (item.asset as? AVURLAsset)?.url.path ?? self?.media?.url.path ?? ""
                    self?.applyFailure(
                        MediaPlaybackFailure.classify(
                            exists: FileManager.default.fileExists(atPath: path),
                            fileSize: self?.media?.fileSize ?? 0,
                            kind: self?.media?.kind ?? .video,
                            playerError: item.error
                        )
                    )
                default:
                    break
                }
            }
        }
    }

    private func notePlayerTime(_ time: CMTime) {
        guard !isScrubbing, pendingProxySeek == nil else { return }
        let seconds = time.seconds
        guard seconds.isFinite else { return }
        currentSeconds = clampedTime(seconds)
        if duration <= 0, let itemDuration = player.currentItem?.duration.seconds, itemDuration.isFinite, itemDuration > 0 {
            duration = itemDuration
        }
    }

    private func noteDuration(_ seconds: Double) {
        guard seconds.isFinite, seconds > 0 else { return }
        if usesPlaybackProxy, duration > seconds + 0.75 { return }
        duration = seconds
    }

    private func seek(to seconds: Double, precise: Bool) {
        if usesWebKitPlayback {
            pendingWebKitSeek = seconds
            return
        }
        if usesPlaybackProxy, proxyJob?.isComplete != true {
            let available = player.currentItem?.duration.seconds ?? 0
            let buffered = available.isFinite && available > 0.2 && seconds <= available - 0.15
            if !buffered {
                pendingProxySeek = seconds
                player.pause()
                return
            }
        }
        pendingProxySeek = nil
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        if precise {
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        } else {
            let slop = CMTime(seconds: 0.12, preferredTimescale: 600)
            player.seek(to: time, toleranceBefore: slop, toleranceAfter: slop)
        }
    }

    private func snapshotCurrentTime() -> Double {
        if usesWebKitPlayback {
            return currentSeconds
        }
        let t = player.currentTime().seconds
        if t.isFinite, t > 0.05 {
            return clampedTime(t)
        }
        return currentSeconds
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

enum MediaPan {
    /// Two-finger trackpad pan. Default matches Preview: content follows fingers and honors System Settings → Natural scrolling.
    static func twoFingerDelta(x: CGFloat, y: CGFloat, invert: Bool) -> CGSize {
        let followFingers = CGSize(width: -x, height: y)
        if invert {
            return CGSize(width: -followFingers.width, height: -followFingers.height)
        }
        return followFingers
    }
}
