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
        view.load(url)
        return view
    }

    func updateNSView(_ nsView: PlayerContainer, context: Context) {
        nsView.isMuted = isMuted
        nsView.load(url)
        nsView.setPlaying(isPlaying)
    }

    final class PlayerContainer: NSView {
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
            let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
            let item = AVPlayerItem(asset: asset)
            statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                guard let self, self.wantsPlaying, item.status == .readyToPlay else { return }
                self.player.play()
            }
            player.replaceCurrentItem(with: item)
        }

        func setPlaying(_ playing: Bool) {
            wantsPlaying = playing
            if playing {
                if player.currentItem?.status == .readyToPlay {
                    player.play()
                }
            } else {
                player.pause()
                player.seek(to: .zero)
            }
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
        view.load(url)
        view.setPlaying(isPlaying)
        return view
    }

    func updateNSView(_ nsView: Container, context: Context) {
        nsView.isMuted = isMuted
        nsView.load(url)
        nsView.setPlaying(isPlaying)
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
            statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                guard let self, self.wantsPlaying, item.status == .readyToPlay else { return }
                self.player.play()
            }
            player.replaceCurrentItem(with: item)
        }

        func setPlaying(_ playing: Bool) {
            wantsPlaying = playing
            if playing {
                if player.currentItem?.status == .readyToPlay {
                    player.play()
                }
            } else {
                player.pause()
            }
        }
    }
}
