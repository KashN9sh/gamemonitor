import SwiftUI

struct StatsOverlay: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("GameMonitor")
                .font(.headline)

            Text("Switch → HDMI → карта → Mac → экран")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(appModel.capture.requestedFormatDescription)
                .font(.caption)
            Text(appModel.capture.activeFormatDescription)
                .font(.caption)

            if let hint = appModel.capture.mismatchHint {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.yellow)
            }

            if let usb = appModel.usbInfo {
                HStack(spacing: 4) {
                    Image(systemName: usb.speed.isUSB3 ? "bolt.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(usb.speed.isUSB3 ? .green : .orange)
                    Text(usb.speed.label)
                }
                .font(.caption2)
            }

            Text("Апскейл: \(appModel.upscaleMode.title)")
                .font(.caption2)

            Group {
                Text(String(format: "FPS UVC wall-clock: %.1f", appModel.capture.uvcFps))
                Text(String(format: "FPS UVC PTS: %.1f", appModel.capture.ptsFps))
                if appModel.capture.sourceSampleDuration > 0 {
                    let durFps = 1.0 / appModel.capture.sourceSampleDuration
                    Text(String(
                        format: "Sample duration: %.1f мс (%.0f fps)",
                        appModel.capture.sourceSampleDuration * 1000, durFps
                    ))
                }
                Text(String(format: "FPS экран: %.1f", appModel.presentedFps))
                Text(String(format: "GPU: %.2f мс", appModel.gpuMilliseconds))
            }
            .font(.caption)

            if appModel.capture.configuredFrameRate > 0 {
                Text("Цель UVC: \(Int(appModel.capture.configuredFrameRate)) fps")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if appModel.capture.actualMinFrameDurationSeconds > 0,
               appModel.capture.configuredFrameRate > 0 {
                let actualFps = 1.0 / appModel.capture.actualMinFrameDurationSeconds
                let target = appModel.capture.configuredFrameRate
                if abs(actualFps - target) > target * 0.1 {
                    Text(String(format: "⚠️ minFrameDuration ≈ %.0f fps (сессия перетёрла)", actualFps))
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }

            Text("Render dropped: \(appModel.droppedFrames) | AVF dropped: \(appModel.capture.droppedSampleCount)")
                .font(.caption2)

            Text(appModel.capture.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(appModel.audio.statusMessage)
                .font(.caption2)
                .foregroundStyle(audioStatusColor)
        }
        .padding(12)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }

    private var audioStatusColor: Color {
        let message = appModel.audio.statusMessage.lowercased()
        if message.contains("restart") || message.contains("не найдено") || message.contains("ошибка") {
            return .yellow
        }
        return .white.opacity(0.7)
    }
}
