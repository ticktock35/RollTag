import SwiftUI

struct DualScreenPlayerView: View {
    @Bindable var model: AppModel

    var body: some View {
        ZStack {
            HSplitView {
                PlayerPaneView(model: model)
                    .frame(minWidth: 360, minHeight: 240)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                InspectorView(model: model)
                    .frame(minWidth: 220, idealWidth: 320, maxWidth: 640)
                    .frame(maxHeight: .infinity)
            }
            if model.playback.isFullscreen {
                FullscreenPlayerView(model: model)
                    .ignoresSafeArea()
                    .zIndex(20)
            }
        }
        .frame(minWidth: 720, minHeight: 420)
        .background(WindowIDMarker(id: AppModel.playerStageWindowID))
        .onAppear {
            model.notePlayerStageAppeared()
        }
        .onDisappear {
            model.notePlayerStageClosed()
        }
    }
}
