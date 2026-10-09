import AVFoundation
import AppKit
import SwiftUI

struct PlayerPaneView: View {
    @Bindable var model: AppModel
    var fillsScreen: Bool = false

    var body: some View {
        ZStack {
            Color.black
            ZoomableMediaView(playback: model.playback, invertTwoFingerPan: model.preference.invertTwoFingerPan) {
                mediaContent
            }
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
                    PlayerOriginalStillView(url: media.url)
                    if model.playback.showsDecodedVideoFrame, !model.playback.isFullscreen || fillsScreen {
                        SharedPlayerLayer(player: model.playback.player)
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
                PlayerOriginalStillView(url: media.url)
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
    @State private var chromeVisible = true
    @State private var hoveringTop = false
    @State private var hoveringBottom = false
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            PlayerPaneView(model: model, fillsScreen: true)
            VStack(spacing: 0) {
                hoverStrip(height: 56) { hoveringTop = $0 }
                Spacer()
                hoverStrip(height: 96) { hoveringBottom = $0 }
            }
            VStack(spacing: 0) {
                topBanner
                    .opacity(chromeVisible ? 1 : 0)
                    .onHover { hoveringTop = $0 }
                Spacer()
                PlaybackControls(
                    playback: model.playback,
                    compact: false,
                    shortcutHint: model.preference.shortcuts.playbackHint
                )
                .padding(16)
                .opacity(chromeVisible ? 1 : 0)
                .onHover { hoveringBottom = $0 }
            }
            .allowsHitTesting(chromeVisible)
            .animation(.easeInOut(duration: 0.22), value: chromeVisible)
        }
        .onAppear { revealChrome() }
        .onChange(of: model.focusedFootage?.id) { revealChrome() }
        .onChange(of: hoveringTop) { updateChromeHover() }
        .onChange(of: hoveringBottom) { updateChromeHover() }
        .onChange(of: model.playback.isScrubbing) { _, scrubbing in
            if scrubbing {
                revealChrome()
            } else {
                scheduleHide()
            }
        }
        .onDisappear { hideTask?.cancel() }
    }

    private var topTitle: String {
        guard let footage = model.focusedFootage else {
            return model.playback.media?.filename ?? ""
        }
        let warehouse = model.warehouses.first { $0.id == footage.warehouseID }?.preference.name ?? ""
        let folder = footage.directoryPath
        if !warehouse.isEmpty, !folder.isEmpty {
            return "\(warehouse)/\(folder)"
        }
        if !warehouse.isEmpty { return warehouse }
        if !folder.isEmpty { return folder }
        return footage.filename
    }

    private var topBanner: some View {
        Text(topTitle)
            .font(.headline)
            .foregroundStyle(.white)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.black.opacity(0.42))
    }

    private func hoverStrip(height: CGFloat, setHover: @escaping (Bool) -> Void) -> some View {
        Color.clear
            .frame(height: height)
            .contentShape(Rectangle())
            .onHover(perform: setHover)
    }

    private func updateChromeHover() {
        if hoveringTop || hoveringBottom {
            revealChrome()
        } else {
            scheduleHide()
        }
    }

    private func revealChrome() {
        chromeVisible = true
        scheduleHide()
    }

    private func scheduleHide() {
        hideTask?.cancel()
        if hoveringTop || hoveringBottom || model.playback.isScrubbing {
            return
        }
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            if hoveringTop || hoveringBottom || model.playback.isScrubbing {
                return
            }
            chromeVisible = false
        }
    }
}

private struct ZoomableMediaView<Content: View>: View {
    @Bindable var playback: PreviewPlayback
    var invertTwoFingerPan: Bool
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geo in
            ZStack {
                content
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(playback.zoomScale)
                    .offset(playback.zoomOffset)
                MediaZoomCatcher(playback: playback, viewport: geo.size, invertTwoFingerPan: invertTwoFingerPan)
            }
        }
        .clipped()
    }
}

private struct MediaZoomCatcher: NSViewRepresentable {
    var playback: PreviewPlayback
    var viewport: CGSize
    var invertTwoFingerPan: Bool

    func makeNSView(context: Context) -> MediaZoomCatcherView {
        let view = MediaZoomCatcherView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: MediaZoomCatcherView, context: Context) {
        context.coordinator.playback = playback
        context.coordinator.viewport = viewport
        context.coordinator.invertTwoFingerPan = invertTwoFingerPan
        nsView.coordinator = context.coordinator
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(playback: playback, viewport: viewport, invertTwoFingerPan: invertTwoFingerPan)
    }

    @MainActor
    final class Coordinator {
        var playback: PreviewPlayback
        var viewport: CGSize
        var invertTwoFingerPan: Bool

        init(playback: PreviewPlayback, viewport: CGSize, invertTwoFingerPan: Bool) {
            self.playback = playback
            self.viewport = viewport
            self.invertTwoFingerPan = invertTwoFingerPan
        }

        func magnify(by factor: CGFloat) {
            playback.setZoom(playback.zoomScale * factor)
            playback.clampOffset(in: viewport)
        }

        func pan(by delta: CGSize) {
            guard playback.zoomScale > 1 else { return }
            playback.zoomOffset = CGSize(
                width: playback.zoomOffset.width + delta.width,
                height: playback.zoomOffset.height + delta.height
            )
            playback.clampOffset(in: viewport)
        }
    }
}

private final class MediaZoomCatcherView: NSView {
    var coordinator: MediaZoomCatcher.Coordinator?
    private var lastDrag: NSPoint?
    private var holdOrigin: NSPoint?
    private var panning = false

    override var acceptsFirstResponder: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        self
    }

    override func magnify(with event: NSEvent) {
        coordinator?.magnify(by: 1 + event.magnification)
    }

    override func scrollWheel(with event: NSEvent) {
        if event.hasPreciseScrollingDeltas, coordinator?.playback.zoomScale ?? 1 > 1 {
            let invert = coordinator?.invertTwoFingerPan ?? false
            coordinator?.pan(
                by: MediaPan.twoFingerDelta(
                    x: event.scrollingDeltaX,
                    y: event.scrollingDeltaY,
                    invert: invert
                )
            )
            return
        }
        super.scrollWheel(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        lastDrag = point
        holdOrigin = point
        panning = false
        coordinator?.playback.beginHoldSpeed()
    }

    override func mouseDragged(with event: NSEvent) {
        let now = convert(event.locationInWindow, from: nil)
        if !panning, let origin = holdOrigin {
            let moved = hypot(now.x - origin.x, now.y - origin.y)
            if moved > 4, (coordinator?.playback.zoomScale ?? 1) > 1 {
                panning = true
                coordinator?.playback.endHoldSpeed()
            }
        }
        if panning, let last = lastDrag {
            coordinator?.pan(by: CGSize(width: now.x - last.x, height: now.y - last.y))
        }
        lastDrag = now
    }

    override func mouseUp(with event: NSEvent) {
        coordinator?.playback.endHoldSpeed()
        lastDrag = nil
        holdOrigin = nil
        panning = false
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

private struct PlayerOriginalStillView: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Color.black
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            }
        }
        .task(id: url) {
            image = nil
            let screen = NSScreen.main
            let edge = ThumbnailService.playerStillMaxEdge(
                for: screen?.frame.size ?? CGSize(width: 1920, height: 1080),
                scale: screen?.backingScaleFactor ?? 2
            )
            image = await ThumbnailService.previewFrame(url: url, maxEdge: edge)
        }
    }
}
