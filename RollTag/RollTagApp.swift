import AppKit
import SwiftUI

final class RollTagAppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.stop()
    }
}

@main
struct RollTagApp: App {
    @NSApplicationDelegateAdaptor(RollTagAppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 1180, minHeight: 760)
                .onAppear {
                    appDelegate.model = model
                    model.start()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(String(localized: "warehouse.add")) {
                    model.chooseWarehouseFolder()
                }
                .keyboardShortcut("o", modifiers: [.command])
            }
            CommandMenu(String(localized: "menu.warehouse")) {
                Button(String(localized: "warehouse.add")) {
                    model.chooseWarehouseFolder()
                }
                .keyboardShortcut("o", modifiers: [.command])
                Button(String(localized: "duplicates.title")) {
                    model.showDuplicates = true
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                Divider()
                Button(String(localized: "status.rescan")) {
                    Task { await model.reconcileOnlineWarehouses() }
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
            CommandMenu(String(localized: "menu.tag")) {
                Button(String(localized: "selection.all")) {
                    model.selectAllVisible()
                }
                .keyboardShortcut("a", modifiers: [.command])
                Button(String(localized: "selection.clear")) {
                    model.exitFullscreenOrClearSelection()
                }
                if model.showsAITagging {
                    Divider()
                    Button(String(localized: "ai.tag.selection")) {
                        model.tagSelectedWithAI()
                    }
                    .keyboardShortcut("t", modifiers: [.command, .option])
                    .disabled(!model.canTagWithAI)
                }
            }
            CommandMenu(String(localized: "menu.playback")) {
                Button(String(localized: "player.playPause")) {
                    if AppModel.isTrimKeyWindow {
                        NotificationCenter.default.post(name: .trimTogglePlay, object: nil)
                    } else {
                        model.playback.togglePlayPause()
                    }
                }
                .disabled(!model.playback.canPlay && !AppModel.isTrimKeyWindow)
                Button(String(localized: "player.fullscreen")) {
                    model.toggleSelectedFullscreen()
                }
                .disabled(model.focusedFootageID == nil && model.playback.media == nil && !model.playback.isFullscreen)
            }
            CommandGroup(after: .sidebar) {
                Button(String(localized: "duplicates.title")) {
                    model.showDuplicates = true
                }
                Button(String(localized: "shortcuts.title")) {
                    model.showShortcuts = true
                }
            }
            CommandGroup(after: .help) {
                Button(String(localized: "shortcuts.title")) {
                    model.showShortcuts = true
                }
                .keyboardShortcut("/", modifiers: .command)
            }
        }
        .defaultSize(width: 1280, height: 800)

        Settings {
            SettingsView(model: model)
        }

        Window(String(localized: "duplicates.title"), id: "duplicates") {
            DuplicatesView(model: model)
        }
        .keyboardShortcut("d", modifiers: [.command, .shift])

        Window(String(localized: "shortcuts.title"), id: "shortcuts") {
            ShortcutsView(model: model)
        }
        .defaultSize(width: 540, height: 640)

        Window(String(localized: "trim.title"), id: "trim") {
            if let session = model.trimSession,
               let footage = model.footage(id: session.footageID) {
                TrimEditorView(model: model, footage: footage, url: session.url)
            } else {
                ContentUnavailableView(
                    String(localized: "trim.title"),
                    systemImage: "scissors",
                    description: Text(String(localized: "trim.unavailable"))
                )
                .frame(minWidth: 480, minHeight: 320)
            }
        }
        .defaultSize(width: 800, height: 720)
    }
}
