import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        Group {
            if appModel.isFullscreen {
                FullscreenPlayerView(appModel: appModel)
            } else {
                normalLayout
            }
        }
        .background(
            WindowAccessor { window in
                appModel.registerMainWindow(window)
            }
        )
        .onDisappear { appModel.persistSettings() }
    }

    private var normalLayout: some View {
        VStack(spacing: 16) {
            Text("GameMonitor")
                .font(.title2.bold())

            Text("Switch (HDMI) → Cam Link → Mac → Studio Display")
                .foregroundStyle(.secondary)

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Разрешение и FPS задаёт Switch", systemImage: "gamecontroller")
                        .font(.headline)
                    Text("Режим «Авто» на консоли подстраивается под TV. GameMonitor **не меняет** HDMI — только показывает то, что пришло с карты.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Чтобы сменить картинку: **Настройки Switch → TV → выберите 1440p / 1080p / 4K вручную** (не «Авто»).")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if appModel.capture.uvcUnchangedAfterPresetSwitch || appModel.capture.mismatchHint != nil {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(appModel.capture.mismatchHint ?? "Режим UVC не изменился после смены пресета.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                .padding(10)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }

            if !appModel.rendererAvailable {
                Text("⚠️ Metal недоступен на этом Mac. Видеопросмотр не будет работать.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 12) {
                Button("Старт") { appModel.start() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!appModel.rendererAvailable)
                Button("Стоп") { appModel.stop() }
                Button("Настройки…") { openSettings() }
            }

            GroupBox("Статус") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(appModel.capture.statusMessage)
                    Text(appModel.capture.requestedFormatDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(appModel.capture.activeFormatDescription)
                        .font(.caption)
                    Text("Апскейл: \(appModel.upscaleMode.title)")
                        .font(.caption)
                    Text(String(format: "FPS UVC: %.1f", appModel.capture.uvcFps))
                    Text(String(format: "FPS экран: %.1f", appModel.presentedFps))
                    Text(appModel.audio.statusMessage)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            PlayerView(appModel: appModel)
                .frame(width: 640, height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(24)
        .frame(minWidth: 720, minHeight: 600)
    }

    private func openSettings() {
        let controller = NSHostingController(rootView: SettingsView(appModel: appModel))
        let window = NSWindow(contentViewController: controller)
        window.title = "Настройки GameMonitor"
        window.styleMask = [.titled, .closable]
        // .floating, чтобы окно гарантированно всплыло поверх native fullscreen Space
        // плеера. macOS откроет его в собственном Space, но иногда возвращает фокус
        // на fullscreen окно — floating это нивелирует.
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

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

/// Полноэкранный layout: один MetalCaptureSurface на весь contentView, поверх — overlay.
/// Никакого второго NSWindow, никакого NSHostingView. Окно просто переключается в native
/// fullscreen Space, а SwiftUI меняет layout — это самый чистый Apple-way.
struct FullscreenPlayerView: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let renderer = appModel.renderer {
                MetalCaptureSurface(renderer: renderer)
                    .ignoresSafeArea()
            }
            if appModel.showStatsOverlay {
                StatsOverlay(appModel: appModel)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
