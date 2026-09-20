import AppKit
import Foundation

final class VolumeMonitor {
    private var tokens: [NSObjectProtocol] = []

    func start(onChange: @escaping () -> Void) {
        stop()
        let center = NSWorkspace.shared.notificationCenter
        tokens = [
            center.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { _ in
                onChange()
            },
            center.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { _ in
                onChange()
            },
        ]
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        tokens.forEach { center.removeObserver($0) }
        tokens.removeAll()
    }
}
