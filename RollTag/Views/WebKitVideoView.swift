import SwiftUI
import WebKit

struct WebKitVideoView: NSViewRepresentable {
    var playback: PreviewPlayback
    var url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(playback: playback)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(context.coordinator, name: "rolltag")
        let view = WKWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        view.allowsMagnification = false
        context.coordinator.webView = view
        context.coordinator.load(url)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.playback = playback
        context.coordinator.webView = view
        context.coordinator.load(url)
        context.coordinator.sync(playback)
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading()
        view.configuration.userContentController.removeScriptMessageHandler(forName: "rolltag")
        coordinator.removePreviewHTML()
        coordinator.webView = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler {
        var playback: PreviewPlayback
        weak var webView: WKWebView?
        private var loadedURL: URL?
        private var previewHTML: URL?

        init(playback: PreviewPlayback) {
            self.playback = playback
        }

        func load(_ url: URL) {
            guard loadedURL != url else { return }
            removePreviewHTML()
            loadedURL = url
            let directory = url.deletingLastPathComponent()
            let htmlURL = directory.appendingPathComponent(".rolltag-preview.html")
            let html = WebKitVideoPlayback.pageHTML(fileName: url.lastPathComponent)
            do {
                try html.write(to: htmlURL, atomically: true, encoding: .utf8)
                previewHTML = htmlURL
                webView?.loadFileURL(htmlURL, allowingReadAccessTo: directory)
            } catch {
                playback.noteWebKitFailed()
            }
        }

        func removePreviewHTML() {
            if let previewHTML {
                try? FileManager.default.removeItem(at: previewHTML)
                self.previewHTML = nil
            }
        }

        func sync(_ playback: PreviewPlayback) {
            let rate = playback.isHoldSpeed ? PreviewPlayback.holdRate : 1
            let shouldPlay = playback.isPlaying
            let seconds = playback.pendingWebKitSeek ?? (playback.isScrubbing ? playback.currentSeconds : nil)
            let seekJS = seconds.map { "v.currentTime = \($0);" } ?? ""
            let script = """
            (function() {
              const v = document.getElementById('v');
              if (!v) return;
              v.playbackRate = \(rate);
              \(seekJS)
              if (\(shouldPlay) && v.paused) { v.play(); }
              if (!\(shouldPlay) && !v.paused) { v.pause(); }
            })();
            """
            webView?.evaluateJavaScript(script, completionHandler: nil)
            if !playback.isScrubbing {
                playback.pendingWebKitSeek = nil
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["t"] as? String else { return }
            switch type {
            case "time":
                let seconds = (body["s"] as? Double) ?? 0
                let duration = (body["d"] as? Double) ?? 0
                playback.noteWebKitTime(seconds, duration: duration)
            case "duration":
                playback.noteWebKitTime(playback.currentSeconds, duration: (body["d"] as? Double) ?? 0)
            case "ended":
                playback.noteWebKitEnded()
            case "error":
                playback.noteWebKitFailed()
            default:
                break
            }
        }
    }
}
