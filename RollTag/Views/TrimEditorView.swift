import AVFoundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name {
    static let trimTogglePlay = Notification.Name("RollTag.trimTogglePlay")
}

struct TrimEditorView: View {
    @Bindable var model: AppModel
    let footage: Footage
    let url: URL
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var player: AVPlayer
    @State private var start = 0.0
    @State private var end = 1.0
    @State private var duration = 1.0
    @State private var current = 0.0
    @State private var isPlaying = false
    @State private var filmstrip: [NSImage] = []
    @State private var loop = TrimLoopState()
    @State private var keyMonitor: Any?
    @State private var keyFilter = TrimKeyFilter()

    init(model: AppModel, footage: Footage, url: URL) {
        self.model = model
        self.footage = footage
        self.url = url
        let player = AVPlayer(url: url)
        player.automaticallyWaitsToMinimizeStalling = false
        player.actionAtItemEnd = .pause
        _player = State(initialValue: player)
    }

    var body: some View {
        VStack(spacing: 0) {
            playerPane
            filmstripBar
            timeReadout
            savePanel
        }
        .background(Color.black)
        .background(TrimWindowAnchor())
        .frame(minWidth: 720, minHeight: 620)
        .task(id: url) {
            await loadDuration()
            filmstrip = await TrimService.filmstrip(url: url, duration: duration)
            seek(to: start, play: false)
        }
        .onAppear {
            markTrimWindow()
            installKeyMonitor()
            installTimeObserver()
        }
        .onReceive(NotificationCenter.default.publisher(for: .trimTogglePlay)) { _ in
            togglePlay()
        }
        .onChange(of: start) { _, value in
            loop.start = value
            loop.updateBounds(on: player, onReachedEnd: handleReachedEnd)
        }
        .onChange(of: end) { _, value in
            loop.end = value
            loop.updateBounds(on: player, onReachedEnd: handleReachedEnd)
        }
        .onChange(of: isPlaying) { _, value in loop.isPlaying = value }
        .onDisappear {
            removeKeyMonitor()
            player.volume = 0
            player.pause()
            player.rate = 0
            loop.removeObservers(from: player)
        }
    }

    private var playerPane: some View {
        ZStack {
            Color.black
            SharedPlayerLayer(player: player)
            VStack {
                HStack {
                    Text(footage.filename)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(16)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filmstripBar: some View {
        HStack(spacing: 12) {
            Button {
                togglePlay()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .foregroundStyle(.black)
                    .frame(width: 44, height: 44)
                    .background(Color.white, in: Circle())
            }
            .buttonStyle(.plain)
            .help(String(localized: "player.playPause"))

            TrimFilmstrip(
                images: filmstrip,
                duration: duration,
                start: start,
                end: end,
                current: current
            ) { nextStart, nextEnd, preview in
                applyRange(start: nextStart, end: nextEnd, preview: preview)
            }
            .frame(height: 64)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.black)
    }

    private var timeReadout: some View {
        HStack(spacing: 28) {
            timeField(String(localized: "trim.startTime"), start)
            timeField(String(localized: "trim.endTime"), end)
            timeField(String(localized: "trim.totalDuration"), max(end - start, 0))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black)
    }

    private func timeField(_ title: String, _ seconds: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
            Text(seconds.trimTimecode)
                .font(.title3.monospacedDigit())
                .foregroundStyle(.white)
        }
        .accessibilityElement(children: .combine)
    }

    private var savePanel: some View {
        HStack {
            Spacer()
            Button(String(localized: "trim.export")) {
                presentSavePanel()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(model.isBusy || end <= start)
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func loadDuration() async {
        let asset = AVURLAsset(url: url)
        if let loaded = try? await asset.load(.duration) {
            duration = max(loaded.seconds, TrimService.minimumDuration)
        } else if let known = footage.duration {
            duration = max(known, TrimService.minimumDuration)
        }
        let range = TrimService.clampRange(start: 0, end: duration, duration: duration)
        start = range.start
        end = range.end
        current = start
    }

    private func togglePlay() {
        if isPlaying {
            stopPreview(at: current)
            return
        }
        let from = TrimService.loopPlayhead(current: current, start: start, end: end) ?? current
        seek(to: from, play: true)
    }

    private func applyRange(start nextStart: Double, end nextEnd: Double, preview: Double) {
        let range = TrimService.clampRange(start: nextStart, end: nextEnd, duration: duration)
        start = range.start
        end = range.end
        if isPlaying {
            stopPreview(at: min(max(preview, range.start), range.end))
            return
        }
        seek(to: min(max(preview, range.start), range.end - 0.01), play: false)
    }

    private func seek(to seconds: Double, play: Bool) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        current = seconds
        loop.applyBounds(on: player)
        player.volume = 1
        isPlaying = play
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        if play {
            player.play()
        }
    }

    private func stopPreview(at seconds: Double) {
        loop.cancelWrap()
        player.volume = 0
        player.pause()
        player.rate = 0
        isPlaying = false
        current = min(max(seconds, start), end)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            if !isPlaying {
                player.volume = 1
            }
        }
    }

    private func handleReachedEnd() {
        guard isPlaying || player.rate > 0 else { return }
        loop.stopAtEnd(on: player) {
            current = end
            isPlaying = false
        }
    }

    private func installTimeObserver() {
        loop.start = start
        loop.end = end
        loop.isPlaying = isPlaying
        loop.install(on: player, onTick: { seconds in
            current = seconds
            if loop.isPlaying, TrimService.reachedOutPoint(current: seconds, end: loop.end) {
                handleReachedEnd()
            }
        }, onReachedEnd: handleReachedEnd)
    }

    private func markTrimWindow() {
        DispatchQueue.main.async {
            let title = String(localized: "trim.title")
            let window = NSApp.keyWindow
                ?? NSApp.windows.first { $0.title == title }
            window?.identifier = NSUserInterfaceItemIdentifier("trim")
        }
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyFilter.binding = model.preference.shortcuts.binding(for: .playPause)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard AppModel.isTrimKeyWindow else { return event }
            if AppModel.isEditingText { return event }
            guard keyFilter.binding.matches(event) else { return event }
            NotificationCenter.default.post(name: .trimTogglePlay, object: nil)
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func presentSavePanel() {
        guard model.warehouses.contains(where: { $0.id == footage.warehouseID }) else { return }
        player.pause()
        isPlaying = false

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.directoryURL = url.deletingLastPathComponent()
        panel.nameFieldStringValue = TrimService.defaultFilename(from: footage.filename)
        panel.title = String(localized: "trim.export")
        panel.message = String(localized: "trim.save.message")
        panel.prompt = String(localized: "trim.export")
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie]

        let accessory = TrimSaveAccessory(source: url)
        panel.delegate = accessory
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        Task { await saveClip(to: destination) }
    }

    private func saveClip(to destination: URL) async {
        let saved = await model.exportTrim(
            footageID: footage.id,
            start: start,
            end: end,
            destination: destination
        )
        if saved {
            dismissWindow(id: "trim")
        }
    }
}

private final class TrimSaveAccessory: NSObject, NSOpenSavePanelDelegate {
    let source: URL

    init(source: URL) {
        self.source = source
    }

    func panel(_ sender: Any, validate url: URL) throws {
        if url.standardizedFileURL.resolvingSymlinksInPath()
            == source.standardizedFileURL.resolvingSymlinksInPath() {
            throw TrimSaveError.overwriteSource
        }
    }
}

private struct TrimWindowAnchor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.identifier = NSUserInterfaceItemIdentifier("trim")
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.window?.identifier = NSUserInterfaceItemIdentifier("trim")
    }
}

private final class TrimKeyFilter: @unchecked Sendable {
    var binding = ShortcutBinding(keyCode: ShortcutKeys.space)
}

private enum TrimSaveError: LocalizedError {
    case overwriteSource

    var errorDescription: String? {
        String(localized: "trim.save.overwriteSource")
    }
}

@MainActor
private final class TrimLoopState {
    var start = 0.0
    var end = 1.0
    var isPlaying = false
    private var periodic: Any?
    private var boundary: Any?
    private var endNotice: NSObjectProtocol?
    private var wrapping = false

    func install(
        on player: AVPlayer,
        onTick: @escaping (Double) -> Void,
        onReachedEnd: @escaping () -> Void
    ) {
        removeObservers(from: player)
        applyBounds(on: player)
        periodic = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600),
            queue: .main
        ) { time in
            let seconds = time.seconds
            guard seconds.isFinite else { return }
            onTick(seconds)
        }
        installBoundary(on: player, onReachedEnd: onReachedEnd)
        endNotice = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            Task { @MainActor in
                onReachedEnd()
            }
        }
    }

    func updateBounds(on player: AVPlayer, onReachedEnd: @escaping () -> Void) {
        applyBounds(on: player)
        if let boundary {
            player.removeTimeObserver(boundary)
            self.boundary = nil
        }
        installBoundary(on: player, onReachedEnd: onReachedEnd)
    }

    func applyBounds(on player: AVPlayer) {
        let item = player.currentItem
        let stopAt = max(start, end - 1.0 / 60.0)
        item?.forwardPlaybackEndTime = CMTime(seconds: stopAt, preferredTimescale: 600)
        item?.reversePlaybackEndTime = CMTime(seconds: start, preferredTimescale: 600)
    }

    func cancelWrap() {
        wrapping = false
    }

    func stopAtEnd(on player: AVPlayer, finished: @escaping () -> Void) {
        guard !wrapping else { return }
        wrapping = true
        player.volume = 0
        player.pause()
        player.rate = 0
        applyBounds(on: player)
        let time = CMTime(seconds: end, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                player.volume = 1
                self?.wrapping = false
                finished()
            }
        }
    }

    func removeObservers(from player: AVPlayer) {
        if let periodic {
            player.removeTimeObserver(periodic)
            self.periodic = nil
        }
        if let boundary {
            player.removeTimeObserver(boundary)
            self.boundary = nil
        }
        if let endNotice {
            NotificationCenter.default.removeObserver(endNotice)
            self.endNotice = nil
        }
        wrapping = false
    }

    private func installBoundary(on player: AVPlayer, onReachedEnd: @escaping () -> Void) {
        let time = CMTime(seconds: end, preferredTimescale: 600)
        boundary = player.addBoundaryTimeObserver(forTimes: [NSValue(time: time)], queue: .main) {
            onReachedEnd()
        }
    }
}

private struct TrimFilmstrip: View {
    let images: [NSImage]
    let duration: Double
    let start: Double
    let end: Double
    let current: Double
    var onChange: (Double, Double, Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let height = geo.size.height
            let startX = x(start, width: width)
            let endX = x(end, width: width)
            ZStack(alignment: .leading) {
                filmstripRow(opacity: 0.28)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                filmstripRow(opacity: 1)
                    .mask(alignment: .leading) {
                        Rectangle()
                            .frame(width: max(8, endX - startX), height: height)
                            .offset(x: startX)
                    }

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(red: 1, green: 0.84, blue: 0), lineWidth: 3)
                    .frame(width: max(24, endX - startX), height: height)
                    .offset(x: startX)

                handle.position(x: startX, y: height / 2)
                handle.position(x: endX, y: height / 2)

                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: height - 6)
                    .offset(x: x(current, width: width) - 1)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let time = seconds(for: value.location.x, width: width)
                        if abs(value.startLocation.x - startX) <= abs(value.startLocation.x - endX) {
                            onChange(time, end, time)
                        } else {
                            onChange(start, time, time)
                        }
                    }
            )
        }
    }

    private func filmstripRow(opacity: Double) -> some View {
        HStack(spacing: 0) {
            if images.isEmpty {
                ForEach(0..<TrimService.filmstripCount, id: \.self) { _ in
                    Color.white.opacity(0.08)
                }
            } else {
                ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.low)
                        .scaledToFill()
                }
            }
        }
        .opacity(opacity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var handle: some View {
        Capsule()
            .fill(Color(red: 1, green: 0.84, blue: 0))
            .frame(width: 8, height: 52)
            .shadow(radius: 1)
    }

    private func drag(isStart: Bool, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let time = seconds(for: value.location.x, width: width)
                if isStart {
                    onChange(time, end, time)
                } else {
                    onChange(start, time, time)
                }
            }
    }

    private func x(_ time: Double, width: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(min(max(time / duration, 0), 1)) * width
    }

    private func seconds(for x: CGFloat, width: CGFloat) -> Double {
        guard width > 0, duration > 0 else { return 0 }
        return Double(min(max(x / width, 0), 1)) * duration
    }
}

private extension Double {
    var trimTimecode: String {
        PlaybackClock.formatPrecise(self)
    }
}
