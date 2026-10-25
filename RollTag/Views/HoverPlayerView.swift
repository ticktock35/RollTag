import AVFoundation
import AppKit
import SwiftUI

struct HoverPlayerView: NSViewRepresentable {
    let url: URL
    var isPlaying: Bool
    var isMuted: Bool = true

    func makeNSView(context: Context) -> PlayerContainer {
        let view = PlayerContainer()
        view.isMuted = isMuted
        return view
    }

    func updateNSView(_ nsView: PlayerContainer, context: Context) {
        nsView.isMuted = isMuted
        nsView.setPlaying(isPlaying, url: url)
    }

    final class PlayerContainer: NSView {
        private let player = AVPlayer()
        private let playerLayer = AVPlayerLayer()
        private var currentURL: URL?
        private var statusObservation: NSKeyValueObservation?
        private var revealTimer: Timer?
        private var revealAttempts = 0
        private var wantsPlaying = false
        var isMuted: Bool = true {
            didSet { player.isMuted = isMuted }
        }

        override var isOpaque: Bool { false }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.backgroundColor = NSColor.clear.cgColor
            playerLayer.player = player
            playerLayer.videoGravity = .resizeAspect
            playerLayer.backgroundColor = NSColor.clear.cgColor
            playerLayer.isHidden = true
            layer?.addSublayer(playerLayer)
            player.isMuted = isMuted
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layout() {
            super.layout()
            playerLayer.frame = bounds
        }

        func load(_ url: URL) {
            guard currentURL != url else { return }
            currentURL = url
            statusObservation = nil
            revealTimer?.invalidate()
            revealTimer = nil
            playerLayer.isHidden = true
            let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
            let item = AVPlayerItem(asset: asset)
            item.preferredMaximumResolution = ThumbnailService.hoverMaxResolution
            statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                guard item.status == .readyToPlay else { return }
                DispatchQueue.main.async {
                    guard let self, self.wantsPlaying else { return }
                    self.player.play()
                    self.startRevealTimer()
                }
            }
            player.replaceCurrentItem(with: item)
        }

        func setPlaying(_ playing: Bool, url: URL) {
            wantsPlaying = playing
            if playing {
                load(url)
                if player.currentItem?.status == .readyToPlay {
                    player.play()
                    startRevealTimer()
                }
            } else {
                unload()
            }
        }

        private func startRevealTimer() {
            guard revealTimer == nil else { return }
            revealAttempts = 0
            revealTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] timer in
                guard let self, self.wantsPlaying else {
                    timer.invalidate()
                    return
                }
                self.revealAttempts += 1
                if self.playerLayer.isReadyForDisplay {
                    self.playerLayer.isHidden = false
                    timer.invalidate()
                    self.revealTimer = nil
                    return
                }
                if self.revealAttempts > 90 {
                    timer.invalidate()
                    self.revealTimer = nil
                }
            }
        }

        private func unload() {
            wantsPlaying = false
            statusObservation = nil
            revealTimer?.invalidate()
            revealTimer = nil
            revealAttempts = 0
            playerLayer.isHidden = true
            currentURL = nil
            player.pause()
            player.currentItem?.asset.cancelLoading()
            player.replaceCurrentItem(with: nil)
        }
    }
}

struct IndependentPlayerView: NSViewRepresentable {
    let url: URL
    var isPlaying: Bool
    var isMuted: Bool = true

    func makeNSView(context: Context) -> Container {
        let view = Container()
        view.isMuted = isMuted
        return view
    }

    func updateNSView(_ nsView: Container, context: Context) {
        nsView.isMuted = isMuted
        nsView.setPlaying(isPlaying, url: url)
    }

    final class Container: NSView {
        private let player = AVPlayer()
        private let playerLayer = AVPlayerLayer()
        private var currentURL: URL?
        private var statusObservation: NSKeyValueObservation?
        private var wantsPlaying = false
        var isMuted: Bool = true {
            didSet { player.isMuted = isMuted }
        }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            playerLayer.player = player
            playerLayer.videoGravity = .resizeAspect
            layer?.backgroundColor = NSColor.black.cgColor
            layer?.addSublayer(playerLayer)
            player.isMuted = isMuted
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layout() {
            super.layout()
            playerLayer.frame = bounds
        }

        func load(_ url: URL) {
            guard currentURL != url else { return }
            currentURL = url
            statusObservation = nil
            let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
            let item = AVPlayerItem(asset: asset)
            item.preferredMaximumResolution = ThumbnailService.previewMaxResolution
            statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                guard let self, self.wantsPlaying, item.status == .readyToPlay else { return }
                self.player.play()
            }
            player.replaceCurrentItem(with: item)
        }

        func setPlaying(_ playing: Bool, url: URL) {
            wantsPlaying = playing
            if playing {
                load(url)
                if player.currentItem?.status == .readyToPlay {
                    player.play()
                }
            } else {
                unload()
            }
        }

        private func unload() {
            wantsPlaying = false
            statusObservation = nil
            currentURL = nil
            player.pause()
            player.currentItem?.asset.cancelLoading()
            player.replaceCurrentItem(with: nil)
        }
    }
}
