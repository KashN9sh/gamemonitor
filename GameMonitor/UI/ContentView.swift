import AppKit
import SwiftUI

/// Тонкий диспетчер: native fullscreen → FullscreenPlayerView, иначе MediaPlayerView.
/// Регистрирует main window в AppModel через WindowAccessor — это нужно, чтобы
/// AppModel мог переключать окно в native fullscreen.
struct ContentView: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        Group {
            if appModel.isFullscreen {
                FullscreenPlayerView(appModel: appModel)
            } else {
                MediaPlayerView(appModel: appModel)
            }
        }
        .background(
            WindowAccessor { window in
                appModel.registerMainWindow(window)
            }
        )
        .onDisappear { appModel.persistSettings() }
    }
}

/// Используется как ContentView в обычном (не fullscreen) режиме main window.
/// Оставлен для совместимости со старыми вызовами; реальное наполнение — в MediaPlayerView.
struct PlayerView: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        ZStack {
            Color.black
            if let renderer = appModel.renderer {
                MetalCaptureSurface(renderer: renderer)
            }
            if appModel.showStatsOverlay {
                StatsOverlay(appModel: appModel)
            }
        }
    }
}

/// Полноэкранный layout: full-bleed плеер + glass HUD поверх. Используется,
/// когда main window ушёл в native fullscreen Space.
struct FullscreenPlayerView: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let renderer = appModel.renderer {
                MetalCaptureSurface(renderer: renderer)
                    .ignoresSafeArea()
            }
            if let hint = appModel.capture.mismatchHint, appModel.capture.isRunning {
                MismatchToast(message: hint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 28)
            }
            if appModel.showStatsOverlay && appModel.capture.isRunning {
                StatsOverlay(appModel: appModel)
                    .frame(maxWidth: 320, alignment: .topTrailing)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(20)
            }
            FloatingControlBar(appModel: appModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 28)
                .autoHide(idle: 2.5, forceVisible: !appModel.capture.isRunning)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.dark)
    }
}
