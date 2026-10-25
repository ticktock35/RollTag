import SwiftUI

struct OpenWithMenuContent: View {
    let footage: Footage
    var model: AppModel
    var includeDefault = true

    var body: some View {
        let choices = model.otherAppChoices(for: footage)
        if includeDefault {
            if let defaultApp = choices.first(where: \.isDefault) {
                Button(String(localized: "openWith.app \(defaultApp.name)")) {
                    model.openInOtherApp(footage, appURL: defaultApp.url)
                }
            } else {
                Button(String(localized: "openWith.default")) {
                    model.openInOtherApp(footage, appURL: nil)
                }
            }
        }
        let others = choices.filter { !$0.isDefault }
        if includeDefault, !others.isEmpty {
            Divider()
        }
        ForEach(others) { app in
            Button(String(localized: "openWith.app \(app.name)")) {
                model.openInOtherApp(footage, appURL: app.url)
            }
        }
        if includeDefault || !others.isEmpty {
            Divider()
        }
        Button(String(localized: "openWith.choose")) {
            model.chooseAppToOpen(footage)
        }
    }
}

struct OpenWithActions: View {
    let footage: Footage
    var model: AppModel
    var compact: Bool

    var body: some View {
        VStack(spacing: compact ? 8 : 10) {
            Button {
                let defaultApp = model.otherAppChoices(for: footage).first(where: \.isDefault)
                model.openInOtherApp(footage, appURL: defaultApp?.url)
            } label: {
                Text(String(localized: "openWith.default"))
                    .frame(minWidth: compact ? 140 : 180)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(compact ? .regular : .large)

            Menu {
                OpenWithMenuContent(footage: footage, model: model, includeDefault: false)
            } label: {
                Text(String(localized: "openWith.other"))
            }
            .menuStyle(.borderlessButton)
            .foregroundStyle(.white)
        }
    }
}
