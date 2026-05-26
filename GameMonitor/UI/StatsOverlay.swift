import SwiftUI

/// Glass-карточка со статистикой — рендерится top-trailing поверх плеера.
/// Заменяет старый black-opacity-блок: теперь это полноценный Liquid Glass card,
/// без избыточных текстов (welcome state и mismatch — отдельные overlay-ы).
struct StatsOverlay: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Divider().opacity(0.25)

            formatBlock

            Divider().opacity(0.25)

            metricsBlock

            if let warning = warningText {
                Divider().opacity(0.25)
                Text(warning)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            footer
        }
        .padding(16)
        .frame(minWidth: 240, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.path.ecg")
                .font(.body.weight(.semibold))
                .foregroundStyle(.tint)
            Text("Статистика")
                .font(.headline)
        }
    }

    private var formatBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(appModel.capture.requestedFormatDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(appModel.capture.activeFormatDescription)
                .font(.caption.monospacedDigit())

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
                .foregroundStyle(.secondary)
        }
    }

    private var metricsBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            metricRow("UVC wall-clock", value: String(format: "%.1f", appModel.capture.uvcFps), unit: "fps")
            metricRow("UVC PTS", value: String(format: "%.1f", appModel.capture.ptsFps), unit: "fps")
            if appModel.capture.sourceSampleDuration > 0 {
                let durFps = 1.0 / appModel.capture.sourceSampleDuration
                metricRow(
                    "Sample dur",
                    value: String(format: "%.1f", appModel.capture.sourceSampleDuration * 1000),
                    unit: "мс / \(Int(durFps.rounded())) fps"
                )
            }
            metricRow("Экран", value: String(format: "%.1f", appModel.presentedFps), unit: "fps")
            if appModel.displayFps > 0 {
                metricRow(
                    "VSync",
                    value: String(format: "%.0f", appModel.displayFps),
                    unit: "Hz",
                    secondary: true
                )
            }
            metricRow("GPU", value: String(format: "%.2f", appModel.gpuMilliseconds), unit: "мс")

            if appModel.capture.configuredFrameRate > 0 {
                metricRow(
                    "Цель UVC",
                    value: String(Int(appModel.capture.configuredFrameRate)),
                    unit: "fps",
                    secondary: true
                )
            }

            metricRow(
                "Дропы",
                value: "\(appModel.droppedFrames) / \(appModel.capture.droppedSampleCount)",
                unit: "render / AVF",
                secondary: true
            )
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(appModel.capture.statusMessage)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(appModel.audio.statusMessage)
                .font(.caption2)
                .foregroundStyle(audioStatusColor)
        }
    }

    // MARK: - Helpers

    private var warningText: String? {
        let actual = appModel.capture.actualMinFrameDurationSeconds
        let target = appModel.capture.configuredFrameRate
        guard actual > 0, target > 0 else { return nil }
        let actualFps = 1.0 / actual
        guard abs(actualFps - target) > target * 0.1 else { return nil }
        return String(format: "minFrameDuration ≈ %.0f fps — сессия перетёрла", actualFps)
    }

    private func metricRow(
        _ label: String,
        value: String,
        unit: String,
        secondary: Bool = false
    ) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(secondary ? .tertiary : .secondary)
                .frame(width: 88, alignment: .leading)
            Text(value)
                .font(.caption.monospacedDigit().weight(.medium))
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
    }

    private var audioStatusColor: Color {
        let message = appModel.audio.statusMessage.lowercased()
        if message.contains("restart") || message.contains("не найдено") || message.contains("ошибка") {
            return .yellow
        }
        return .secondary
    }
}
