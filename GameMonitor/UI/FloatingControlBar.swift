import SwiftUI

/// Glass-капсула с управлением плеером. Показывается снизу по центру, прячется по
/// idle через `AutoHideOverlay`. Содержит: Play/Stop, громкость, mute, fullscreen
/// toggle, popover с настройками.
struct FloatingControlBar: View {
    @ObservedObject var appModel: AppModel
    @State private var showSettings: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            playStopButton
            Divider()
                .frame(height: 22)
                .opacity(0.3)
            VolumeControl(audio: appModel.audio)
            Divider()
                .frame(height: 22)
                .opacity(0.3)
            fullscreenButton
            settingsButton
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
    }

    // MARK: - Buttons

    private var playStopButton: some View {
        Button {
            if appModel.capture.isRunning {
                appModel.stop()
            } else {
                appModel.start()
            }
        } label: {
            Image(systemName: appModel.capture.isRunning ? "stop.fill" : "play.fill")
                .font(.title3.weight(.semibold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.glassProminent)
        .tint(appModel.capture.isRunning ? .red : .accentColor)
        .controlSize(.large)
        .disabled(!appModel.rendererAvailable)
        .keyboardShortcut(.return, modifiers: .command)
        .help(appModel.capture.isRunning ? "Стоп (⌘⏎)" : "Старт (⌘⏎)")
    }

    private var fullscreenButton: some View {
        Button {
            if appModel.isFullscreen {
                appModel.exitFullscreen()
            } else {
                appModel.enterFullscreen()
            }
        } label: {
            Image(systemName: appModel.isFullscreen
                ? "arrow.down.right.and.arrow.up.left"
                : "arrow.up.left.and.arrow.down.right")
                .font(.body.weight(.semibold))
                .frame(width: 24, height: 24)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.glass)
        .controlSize(.large)
        .help(appModel.isFullscreen ? "Выйти из полноэкранного режима" : "На весь экран (⌘⇧F)")
    }

    private var settingsButton: some View {
        Button {
            showSettings.toggle()
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.body.weight(.semibold))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
        .popover(isPresented: $showSettings, arrowEdge: .bottom) {
            SettingsView(appModel: appModel)
                .frame(width: 560, height: 600)
        }
        .help("Настройки")
    }
}

/// Компактный регулятор громкости: иконка mute / unmute + slider 0..1.
///
/// Слайдер биндится напрямую к `audio.volume` (Float). Кастомный Binding с
/// «get returns 0 when muted» ломал отзывчивость и confusing hit testing на
/// macOS 26 — сейчас mute это просто отдельная кнопка-toggle, а слайдер всегда
/// показывает реальное значение volume.
private struct VolumeControl: View {
    @ObservedObject var audio: AudioPipeline

    var body: some View {
        HStack(spacing: 10) {
            Button {
                audio.isMuted.toggle()
            } label: {
                Image(systemName: muteIcon)
                    .font(.body.weight(.semibold))
                    .frame(width: 24, height: 24)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help(audio.isMuted ? "Включить звук" : "Без звука")

            Slider(value: $audio.volume, in: 0...1)
                .frame(width: 130)
                .tint(.white)
        }
    }

    private var muteIcon: String {
        if audio.isMuted || audio.volume == 0 { return "speaker.slash.fill" }
        if audio.volume < 0.34 { return "speaker.wave.1.fill" }
        if audio.volume < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}
