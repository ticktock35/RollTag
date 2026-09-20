import AVFoundation
import AVKit
import SwiftUI

struct TrimEditorView: View {
    @Bindable var model: AppModel
    let footage: Footage
    let url: URL
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var player: AVPlayer
    @State private var start = 0.0
    @State private var end = 1.0
    @State private var duration = 1.0

    init(model: AppModel, footage: Footage, url: URL) {
        self.model = model
        self.footage = footage
        self.url = url
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(footage.filename)
                .font(.title3.weight(.semibold))
            VideoPlayer(player: player)
                .frame(minHeight: 280)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack {
                Text(String(localized: "trim.in"))
                Slider(value: $start, in: 0...max(end - 0.1, 0.1))
                Text(start.timecode)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(String(localized: "trim.out"))
                Slider(value: $end, in: min(start + 0.1, duration)...max(duration, 0.2))
                Text(end.timecode)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button(String(localized: "trim.export")) {
                    Task {
                        await model.exportTrim(footageID: footage.id, start: start, end: end)
                        dismissWindow(id: "trim")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.isBusy || end <= start)
            }
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 480)
        .task(id: url) {
            let asset = AVURLAsset(url: url)
            if let loaded = try? await asset.load(.duration) {
                duration = max(loaded.seconds, 0.2)
                end = duration
                start = 0
            }
        }
        .onDisappear {
            player.pause()
        }
    }
}

private extension Double {
    var timecode: String {
        let total = Int(self.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
