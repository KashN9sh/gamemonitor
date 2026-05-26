import SwiftUI

/// Главный экран приложения в обычном (не fullscreen) режиме. Full-bleed плеер,
/// поверх — glass-карточки и floating HUD. Структура inspired by Apple TV / Music.
struct MediaPlayerView: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let renderer = appModel.renderer {
                MetalCaptureSurface(renderer: renderer)
                    .ignoresSafeArea()
                    .opacity(appModel.capture.isRunning ? 1.0 : 0.18)
                    .animation(.smooth(duration: 0.4), value: appModel.capture.isRunning)
            }

            if !appModel.capture.isRunning {
                WelcomeOverlay(appModel: appModel)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }

            if let hint = appModel.capture.mismatchHint, appModel.capture.isRunning {
                MismatchToast(message: hint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 28)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if appModel.capture.isRunning {
                switch appModel.statsDisplayMode {
                case .off:
                    EmptyView()
                case .compact:
                    CompactFPSOverlay(appModel: appModel)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .transition(.opacity)
                case .full:
                    StatsOverlay(appModel: appModel)
                        .frame(maxWidth: 320, alignment: .topTrailing)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(20)
                        .transition(.opacity)
                }
            }

            FloatingControlBar(appModel: appModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 28)
                .autoHide(idle: 2.5, forceVisible: !appModel.capture.isRunning)
        }
        .preferredColorScheme(.dark)
        .animation(.smooth(duration: 0.35), value: appModel.capture.isRunning)
        .animation(.smooth(duration: 0.35), value: appModel.capture.mismatchHint)
        .animation(.smooth(duration: 0.35), value: appModel.statsDisplayMode)
        .onDisappear { appModel.persistSettings() }
    }
}
