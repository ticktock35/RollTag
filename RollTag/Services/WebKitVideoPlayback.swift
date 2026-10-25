import Foundation

enum WebKitVideoPlayback {
    static let extensions: Set<String> = ["webm", "mkv"]

    static func supports(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }

    static func pageHTML(fileName: String) -> String {
        let src = encodedFileName(fileName)
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        html, body { margin: 0; height: 100%; background: #000; overflow: hidden; }
        video { width: 100%; height: 100%; object-fit: contain; background: #000; }
        </style>
        </head>
        <body>
        <video id="v" playsinline preload="auto"></video>
        <script>
        const v = document.getElementById('v');
        v.src = "\(src)";
        function post(msg) {
          if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.rolltag) {
            window.webkit.messageHandlers.rolltag.postMessage(msg);
          }
        }
        v.addEventListener('loadedmetadata', () => post({ t: 'duration', d: v.duration || 0 }));
        v.addEventListener('durationchange', () => post({ t: 'duration', d: v.duration || 0 }));
        v.addEventListener('timeupdate', () => post({ t: 'time', s: v.currentTime || 0, d: v.duration || 0 }));
        v.addEventListener('play', () => post({ t: 'play' }));
        v.addEventListener('pause', () => post({ t: 'pause' }));
        v.addEventListener('ended', () => post({ t: 'ended' }));
        v.addEventListener('error', () => post({ t: 'error' }));
        </script>
        </body>
        </html>
        """
    }

    static func encodedFileName(_ name: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "?#[]")
        return name.addingPercentEncoding(withAllowedCharacters: allowed) ?? name
    }
}
