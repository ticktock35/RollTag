import AppKit
import SwiftUI

struct WindowIDMarker: NSViewRepresentable {
    var id: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.identifier = NSUserInterfaceItemIdentifier(id)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        view.window?.identifier = NSUserInterfaceItemIdentifier(id)
    }
}

final class GridFocusView: NSView {
    override var acceptsFirstResponder: Bool { true }
}

struct GridFocusCatcher: NSViewRepresentable {
    private static weak var current: GridFocusView?

    func makeNSView(context: Context) -> GridFocusView {
        let view = GridFocusView()
        Self.current = view
        return view
    }

    func updateNSView(_ view: GridFocusView, context: Context) {
        Self.current = view
    }

    static func claimFirstResponder() {
        if let view = current, let window = view.window {
            window.makeFirstResponder(view)
            return
        }
        let window = DisplayLayout.taggedWindow(AppModel.libraryWindowID) ?? NSApp.keyWindow
        window?.makeFirstResponder(window?.contentView)
    }
}
