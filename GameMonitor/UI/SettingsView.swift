import SwiftUI

struct SettingsView: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        TabView {
            CaptureSettingsTab(appModel: appModel)
                .tabItem { Label("Захват", systemImage: "video.fill") }

            DisplaySettingsTab(appModel: appModel)
                .tabItem { Label("Дисплей", systemImage: "display") }

            AudioSettingsTab(appModel: appModel)
                .tabItem { Label("Аудио", systemImage: "speaker.wave.2.fill") }

            DiagnosticsTab(appModel: appModel)
                .tabItem { Label("Диагностика", systemImage: "stethoscope") }
        }
        .padding(16)
        .frame(minWidth: 540, minHeight: 580)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Capture

private struct CaptureSettingsTab: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                GlassCard("Источник UVC", icon: "video.fill") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("При Switch «Авто» смена пресета здесь обычно ничего не меняет — UVC остаётся тем же. Сначала задайте разрешение на консоли.")
                            .font(.caption)
                            .foregroundStyle(.orange)

                        if appModel.manualFormatID != nil {
                            Label("Активен ручной формат UVC из вкладки «Диагностика». Пресет игнорируется.",
                                  systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }

                        Picker("Запрос UVC (эксперт)", selection: $appModel.videoPreset) {
                            ForEach(VideoCapturePreset.allCases) { preset in
                                Text(preset.title).tag(preset)
                            }
                        }

                        Text(appModel.videoPreset.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if appModel.capture.isRunning {
                            Button("Применить режим (перезапуск)") {
                                appModel.applyPresetAndRestart()
                            }
                            .buttonStyle(.glassProminent)
                        }
                    }
                }

                GlassCard("Устройство", icon: "cable.connector") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Устройство", selection: $appModel.selectedDeviceID) {
                            ForEach(appModel.devices) { device in
                                Text(device.name).tag(Optional(device.id))
                            }
                        }
                        .onAppear { appModel.reloadDevices() }
                        .onChange(of: appModel.selectedDeviceID) { _, _ in
                            appModel.refreshDeviceMetadata()
                        }

                        Text(appModel.capture.activeFormatDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Spacer()
                            Button("Сохранить") {
                                appModel.persistSettings()
                            }
                            .buttonStyle(.glass)
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
        }
    }
}

// MARK: - Display

private struct DisplaySettingsTab: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                GlassCard("Дисплей", icon: "display") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Экран", selection: $appModel.selectedScreenID) {
                            ForEach(appModel.screens) { screen in
                                Text(screen.name).tag(Optional(screen.id))
                            }
                        }

                        Picker("Апскейл", selection: $appModel.upscaleMode) {
                            ForEach(UpscaleMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .onChange(of: appModel.upscaleMode) { _, _ in
                            appModel.applyUpscaleMode()
                        }

                        Text("MetalFX Spatial — нейронный апскейлер Apple, оптимизирован для игр и работает на Apple Silicon. Без апскейла рендер идёт в нативном размере UVC.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                GlassCard("Поведение", icon: "rectangle.expand.vertical") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Fullscreen при запуске", isOn: $appModel.fullscreenOnLaunch)

                        Picker("Статистика", selection: $appModel.statsDisplayMode) {
                            ForEach(StatsDisplayMode.allCases) { mode in
                                Label(mode.title, systemImage: mode.systemImage).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        Button {
                            appModel.enterFullscreen()
                        } label: {
                            Label("На весь экран сейчас", systemImage: "arrow.up.left.and.arrow.down.right")
                        }
                        .buttonStyle(.glass)
                        .keyboardShortcut("f", modifiers: [.command, .shift])
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
        }
    }
}

// MARK: - Audio

private struct AudioSettingsTab: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                GlassCard("Аудио устройство", icon: "mic.fill") {
                    VStack(alignment: .leading, spacing: 12) {
                        if appModel.audioDevices.isEmpty {
                            Label("Не найдено ни одного audio-устройства. Проверьте, что Cam Link подключён и в Системных настройках macOS → Конфиденциальность → Микрофон разрешён доступ для GameMonitor.",
                                  systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else {
                            Picker("Источник", selection: Binding(
                                get: { appModel.selectedAudioDeviceID ?? "__auto__" },
                                set: { newValue in
                                    appModel.selectedAudioDeviceID = newValue == "__auto__" ? nil : newValue
                                }
                            )) {
                                Text("Авто (по имени видеоустройства)").tag("__auto__")
                                ForEach(appModel.audioDevices) { device in
                                    Text(device.name).tag(device.id)
                                }
                            }
                            .onChange(of: appModel.selectedAudioDeviceID) { _, _ in
                                AppSettings.selectedAudioDeviceID = appModel.selectedAudioDeviceID
                                if appModel.capture.isRunning {
                                    appModel.stop()
                                    appModel.start()
                                }
                            }
                        }

                        Button {
                            appModel.reloadDevices()
                        } label: {
                            Label("Обновить список", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.glass)
                    }
                }

                GlassCard("Громкость", icon: "speaker.wave.2.fill") {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            Image(systemName: appModel.audio.isMuted ? "speaker.slash.fill" : "speaker.wave.1.fill")
                                .frame(width: 22)
                                .foregroundStyle(.secondary)
                            Slider(value: Binding(
                                get: { appModel.audio.volume },
                                set: { appModel.audio.volume = $0 }
                            ), in: 0...1)
                            Image(systemName: "speaker.wave.3.fill")
                                .frame(width: 22)
                                .foregroundStyle(.secondary)
                        }
                        Toggle("Без звука", isOn: Binding(
                            get: { appModel.audio.isMuted },
                            set: { appModel.audio.isMuted = $0 }
                        ))
                        Text(appModel.audio.statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
        }
    }
}

// MARK: - Diagnostics

private struct DiagnosticsTab: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                USBInfoCard(usb: appModel.usbInfo)
                FrameTimingCard(
                    samples: appModel.capture.frameIntervalSamples,
                    targetFps: appModel.capture.configuredFrameRate,
                    uvcFps: appModel.capture.uvcFps,
                    ptsFps: appModel.capture.ptsFps,
                    sourceSampleDuration: appModel.capture.sourceSampleDuration,
                    actualMinFrameDuration: appModel.capture.actualMinFrameDurationSeconds,
                    droppedSamples: appModel.capture.droppedSampleCount
                )
                FormatPickerCard(appModel: appModel)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
        }
        .onAppear {
            appModel.refreshDeviceMetadata()
        }
    }
}

private struct USBInfoCard: View {
    let usb: USBDeviceInfo?

    var body: some View {
        GlassCard("USB", icon: "cable.connector") {
            if let usb {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: usb.speed.isUSB3 ? "bolt.fill" : "exclamationmark.triangle.fill")
                            .font(.title3)
                            .foregroundStyle(usb.speed.isUSB3 ? .green : .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(usb.summary)
                                .font(.body)
                            Text(String(format: "VID 0x%04X · PID 0x%04X · %@", usb.vendorID, usb.productID, usb.versionString))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let warning = usb.bandwidthWarning {
                        Text(warning)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            } else {
                Text("USB-устройство не найдено в IORegistry. Возможно, карта подключена не как USB-устройство.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct FrameTimingCard: View {
    let samples: [Double]
    let targetFps: Double
    let uvcFps: Double
    let ptsFps: Double
    let sourceSampleDuration: Double
    let actualMinFrameDuration: Double
    let droppedSamples: UInt64

    var body: some View {
        let stats = FrameIntervalStats.compute(samples: samples)
        let durationFps = sourceSampleDuration > 0 ? 1.0 / sourceSampleDuration : 0
        let minDurFps = actualMinFrameDuration > 0 ? 1.0 / actualMinFrameDuration : 0

        GlassCard("Тайминг кадров", icon: "waveform.path.ecg") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 16) {
                    statBlock("Wall-clock fps", value: String(format: "%.1f", uvcFps))
                    statBlock("PTS fps", value: String(format: "%.1f", ptsFps))
                    statBlock(
                        "Sample duration",
                        value: sourceSampleDuration > 0
                            ? String(format: "%.1f мс (%.0f fps)", sourceSampleDuration * 1000, durationFps)
                            : "—"
                    )
                    statBlock("Цель", value: targetFps > 0 ? String(format: "%.0f", targetFps) : "—")
                }

                FrameIntervalHistogram(samples: samples, targetFps: targetFps)

                HStack(spacing: 12) {
                    statBlock("Среднее", value: stats.count > 0 ? String(format: "%.1f мс", stats.mean * 1000) : "—")
                    statBlock("σ", value: stats.count > 0 ? String(format: "%.1f мс", stats.stdDev * 1000) : "—")
                    statBlock("min", value: stats.count > 0 ? String(format: "%.1f", stats.min * 1000) : "—")
                    statBlock("max", value: stats.count > 0 ? String(format: "%.1f", stats.max * 1000) : "—")
                    statBlock("вне ±10%", value: stats.count > 0 ? String(format: "%.0f%%", stats.outlierShare * 100) : "—")
                    statBlock("AVF дропы", value: "\(droppedSamples)")
                }
                .font(.caption)

                if actualMinFrameDuration > 0, targetFps > 0,
                   abs(actualMinFrameDuration - 1.0 / targetFps) > (1.0 / targetFps) * 0.1 {
                    Text(String(
                        format: "После старта activeVideoMinFrameDuration = %.1f мс (~%.0f fps), а должно быть 1/%.0f. AVCaptureSession не приняла нашу настройку даже после повторного set'а — это значит, формат как таковой картой не отдаётся, она UVC-уровневым дескриптором не подтверждает 60.",
                        actualMinFrameDuration * 1000, minDurFps, targetFps
                    ))
                    .font(.caption)
                    .foregroundStyle(.red)
                }

                if let analysis = analysis(uvcFps: uvcFps, ptsFps: ptsFps, durationFps: durationFps, targetFps: targetFps) {
                    Text(analysis.message)
                        .font(.caption)
                        .foregroundStyle(analysis.color)
                }
            }
        }
    }

    private struct Analysis {
        let message: String
        let color: Color
    }

    private func analysis(uvcFps: Double, ptsFps: Double, durationFps: Double, targetFps: Double) -> Analysis? {
        guard targetFps > 0, uvcFps > 0 else { return nil }
        let ratio = uvcFps / targetFps

        if ratio >= 0.9 { return nil }

        if abs(uvcFps - ptsFps) > 5 {
            return Analysis(
                message: "Wall-clock и PTS-fps расходятся. Кадры теряются ПОСЛЕ драйвера: AVF дропы выше нуля или замедление в нашей очереди.",
                color: .orange
            )
        }

        if durationFps > 0, abs(durationFps - uvcFps) < 5 {
            return Analysis(
                message: """
                Источник физически отдаёт ~\(Int(uvcFps.rounded())) fps. Sample duration в кадре = ~\(Int(durationFps.rounded())) fps.

                Что проверить:
                • Switch: Системные настройки → Телевизор → Разрешение и Гц вручную выставить 60 Hz (не «Авто»).
                • Кабель HDMI: попробуйте другой шнур, особенно если он 1.4 / короткий комплектный.
                • Cam Link 4K на ezcap может ронять до 25 fps если EDID Mac/входа сообщает PAL.
                • Перезагрузить карту: вынуть/вставить USB при включённом Switch.
                """,
                color: .red
            )
        }

        return Analysis(
            message: "Источник отдаёт \(Int(uvcFps.rounded())) fps вместо \(Int(targetFps)). Проверьте настройки Switch и HDMI-кабель.",
            color: .orange
        )
    }

    private func statBlock(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.monospacedDigit())
        }
    }
}

private struct FormatPickerCard: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        GlassCard("UVC-форматы карты", icon: "list.bullet.rectangle.portrait") {
            VStack(alignment: .leading, spacing: 8) {
                if appModel.manualFormatID != nil {
                    HStack {
                        Text("Активен ручной выбор формата")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Сбросить") {
                            appModel.applyManualFormat(nil)
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                    }
                }

                if appModel.availableFormats.isEmpty {
                    Text("Список пуст. Подключите карту и нажмите «Старт».")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appModel.availableFormats) { fmt in
                        formatRow(fmt)
                        if fmt.id != appModel.availableFormats.last?.id {
                            Divider().opacity(0.25)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func formatRow(_ fmt: FormatDescriptor) -> some View {
        let isActive = appModel.capture.activeFormatDescriptorID == fmt.id
        let isManual = appModel.manualFormatID == fmt.id

        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(fmt.displayLabel)
                        .font(.body.monospacedDigit())
                    if isActive {
                        Text("активный")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .glassEffect(.regular.tint(.green), in: .capsule)
                    }
                    if isManual {
                        Text("ручной")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .glassEffect(.regular.tint(.blue), in: .capsule)
                    }
                }
                HStack(spacing: 8) {
                    if fmt.isMetalCompatibleNV12 {
                        Label("NV12 → Metal", systemImage: "checkmark.seal.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    } else if fmt.isMJPEG {
                        Label("MJPEG (декодер)", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    } else {
                        Text(fmt.pixelFormatName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if fmt.supports60 {
                        Text("60 fps")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }
            }
            Spacer()
            Button("Выбрать") {
                appModel.applyManualFormat(fmt.id)
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .disabled(isManual)
        }
        .padding(.vertical, 4)
    }
}
