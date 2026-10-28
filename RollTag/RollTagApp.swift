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
                .rollTagFontSize(model.preference.fontSizeStep)
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
                Button(String(localized: "gpx.import.menu")) {
                    model.chooseGPXFile()
                }
                .disabled(!model.canImportGPX)
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
                .disabled(model.visibleResults.isEmpty)
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
            CommandGroup(after: .toolbar) {
                Button(String(localized: "view.enlargeFont")) {
                    model.enlargeFont()
                }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(!model.canEnlargeFont)
                Button(String(localized: "view.shrinkFont")) {
                    model.shrinkFont()
                }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(!model.canShrinkFont)
            }
            CommandGroup(after: .help) {
                Button(String(localized: "help.title")) {
                    model.showHelp = true
                }
                Button(String(localized: "shortcuts.title")) {
                    model.showShortcuts = true
                }
                .keyboardShortcut("/", modifiers: .command)
            }
            CommandGroup(before: .windowList) {
                Toggle(isOn: Binding(
                    get: { model.isDualScreen },
                    set: { wantOn in
                        if wantOn != model.isDualScreen {
                            model.toggleDualScreen()
                        }
                    }
                )) {
                    Text(String(localized: "window.dualScreen"))
                }
                .disabled(!model.canUseDualScreen && !model.isDualScreen)
                if model.attachedDisplays.count > 1 {
                    Menu(String(localized: "window.primaryDisplay")) {
                        ForEach(model.attachedDisplays) { screen in
                            Toggle(isOn: Binding(
                                get: { model.resolvedPrimaryDisplayID == screen.id },
                                set: { on in
                                    if on {
                                        model.choosePrimaryDisplay(id: screen.id)
                                    }
                                }
                            )) {
                                Text(screen.name)
                            }
                        }
                    }
                }
            }
        }
        .defaultSize(width: 1280, height: 800)

        Settings {
            SettingsView(model: model)
                .rollTagFontSize(model.preference.fontSizeStep)
        }

        Window(String(localized: "duplicates.title"), id: "duplicates") {
            DuplicatesView(model: model)
                .rollTagFontSize(model.preference.fontSizeStep)
        }
        .keyboardShortcut("d", modifiers: [.command, .shift])

        Window(String(localized: "shortcuts.title"), id: "shortcuts") {
            ShortcutsView(model: model)
                .rollTagFontSize(model.preference.fontSizeStep)
        }
        .defaultSize(width: 540, height: 640)

        Window(String(localized: "help.title"), id: "help") {
            HelpView(model: model)
                .rollTagFontSize(model.preference.fontSizeStep)
        }
        .defaultSize(width: 760, height: 640)

        Window(String(localized: "window.player"), id: AppModel.playerStageWindowID) {
            DualScreenPlayerView(model: model)
                .rollTagFontSize(model.preference.fontSizeStep)
        }
        .defaultSize(width: 1280, height: 800)

        Window(String(localized: "trim.title"), id: "trim") {
            Group {
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
            .rollTagFontSize(model.preference.fontSizeStep)
        }
        .defaultSize(width: 800, height: 720)
    }
}
