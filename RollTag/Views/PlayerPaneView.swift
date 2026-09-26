import AVFoundation
import AppKit
import SwiftUI

struct PlayerPaneView: View {
    @Bindable var model: AppModel
    var fillsScreen: Bool = false

    var body: some View {
        ZStack {
            Color.black
            mediaContent
            if !fillsScreen {
                chrome
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { model.presentFocusedMedia() }
        .onChange(of: model.focusedFootage?.id) {
            model.presentFocusedMedia()
        }
    }

    @ViewBuilder
    private var mediaContent: some View {
        if model.focusedFootage?.status == .missing {
            VStack(spacing: 10) {
                Image(systemName: "eye.slash")
                    .font(.system(size: fillsScreen ? 48 : 28))
                    .foregroundStyle(.white.opacity(0.7))
                Text(model.focusedFootage?.filename ?? "")
                    .font(fillsScreen ? .title2 : .callout)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                Text(String(localized: "player.missing"))
                    .foregroundStyle(.white.opacity(0.7))
                    .font(fillsScreen ? .title3 : .callout)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                if let path = model.focusedFootage?.relativePath, !path.isEmpty {
                    Text(path)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .textSelection(.enabled)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }
        } else if let media = model.playback.media {
            switch media.kind {
            case .video:
                ZStack {
                    if model.playback.isItemLoaded {
                        SharedPlayerLayer(player: model.playback.player)
                    } else {
                        PlayerPosterView(
                            footageID: media.id,
                            warehouseRoot: model.onlineRoot(for: media.id)
                        )
                    }
                    if let message = previewMessage {
                        previewMessageOverlay(message)
                    }
                }
            case .audio:
                VStack(spacing: 12) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: fillsScreen ? 64 : 36))
                        .foregroundStyle(.white.opacity(0.85))
                    Text(media.filename)
                        .font(fillsScreen ? .title2 : .callout)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
            case .image:
                PlayerPosterView(
                    footageID: media.id,
                    warehouseRoot: model.onlineRoot(for: media.id)
                )
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "play.rectangle")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.45))
                Text(String(localized: "player.empty"))
                    .foregroundStyle(.white.opacity(0.55))
                    .font(.callout)
            }
        }
    }

    private var previewMessage: String? {
        if model.playback.isIncompleteFile || model.focusedFootage?.isTooSmallToPreview == true {
            let size = model.focusedFootage?.size ?? model.playback.media?.fileSize ?? 0
            return String(
                format: String(localized: "preview.unavailable.incomplete"),
                locale: .current,
                ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            )
        }
        if model.playback.didFailToLoad {
            return String(localized: "preview.unavailable.codec")
        }
        return nil
    }

    private func previewMessageOverlay(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "film")
                .font(.system(size: fillsScreen ? 36 : 22))
                .foregroundStyle(.white.opacity(0.7))
            Text(message)
                .font(fillsScreen ? .title3 : .callout)
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    private var chrome: some View {
        VStack {
            Spacer()
            PlaybackControls(
                playback: model.playback,
                compact: true,
                shortcutHint: model.preference.shortcuts.playbackHint
            )
        }
        .allowsHitTesting(true)
    }
}

private struct PlaybackControls: View {
    var playback: PreviewPlayback
    var compact: Bool
    var shortcutHint: String

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            if playback.canPlay {
                timeline
            }
            HStack(spacing: compact ? 10 : 16) {
                if playback.canPlay {
                    Button {
                        playback.togglePlayPause()
                    } label: {
                        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                            .font(compact ? .title3 : .title)
                            .padding(compact ? 8 : 12)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "player.playPause"))
                }
                if let name = playback.media?.filename {
                    Text(name)
                        .font(compact ? .caption : .headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Spacer()
                if playback.media != nil {
                    if !compact {
                        Text(shortcutHint)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Button {
                        playback.toggleFullscreen()
                    } label: {
                        Image(systemName: playback.isFullscreen
                              ? "arrow.down.right.and.arrow.up.left"
                              : "arrow.up.left.and.arrow.down.right")
                            .padding(compact ? 8 : 10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "player.fullscreen"))
                }
            }
        }
        .padding(compact ? 12 : 20)
        .background(Color.black.opacity(0.42))
    }

    private var timeline: some View {
        HStack(spacing: 8) {
            Text(PlaybackClock.format(playback.currentSeconds))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.9))
                .frame(minWidth: 44, alignment: .leading)
            Slider(
                value: Binding(
                    get: { min(playback.currentSeconds, max(playback.duration, 0.001)) },
                    set: { playback.scrub(to: $0) }
                ),
                in: 0...max(playback.duration, 0.001)
            ) { editing in
                if editing {
                    playback.beginScrubbing()
                } else {
                    playback.endScrubbing()
                }
            }
            .controlSize(.small)
            .tint(.white)
            .disabled(playback.duration <= 0)
            .help(String(localized: "player.timeline"))
            Text(PlaybackClock.format(playback.duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.9))
                .frame(minWidth: 44, alignment: .trailing)
        }
    }
}

struct FullscreenPlayerView: View {
    @Bindable var model: AppModel

    var body: some View {
        PlayerPaneView(model: model, fillsScreen: true)
            .overlay(alignment: .bottom) {
                PlaybackControls(
                    playback: model.playback,
                    compact: false,
                    shortcutHint: model.preference.shortcuts.playbackHint
                )
                    .padding(16)
            }
    }
}

struct SharedPlayerLayer: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.player = player
        return view
    }

    func updateNSView(_ nsView: PlayerLayerView, context: Context) {
        nsView.player = player
    }
}

final class PlayerLayerView: NSView {
    private let playerLayer = AVPlayerLayer()

    var player: AVPlayer? {
        didSet { playerLayer.player = player }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}

private struct PlayerPosterView: View {
    let footageID: UUID
    let warehouseRoot: URL?
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFit()
            } else {
                Color.clear
            }
        }
        .task(id: footageID) {
            image = nil
            guard let warehouseRoot else { return }
            let thumbURL = ThumbnailService.thumbnailFileURL(warehouseRoot: warehouseRoot, footageID: footageID)
            image = ThumbnailService.loadThumbnail(at: thumbURL, maxEdge: ThumbnailService.storedThumbMaxEdge)
        }
    }
}
