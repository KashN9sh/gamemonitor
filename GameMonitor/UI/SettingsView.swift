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
        .frame(width: 520, height: 540)
        .padding(12)
    }
}

private struct CaptureSettingsTab: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        Form {
            Section("Захват") {
                Text("При Switch «Авто» смена пресета здесь обычно **ничего не меняет** — UVC остаётся тем же. Сначала задайте разрешение на консоли.")
                    .font(.caption)
                    .foregroundStyle(.orange)

                if appModel.manualFormatID != nil {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Активен ручной формат UVC из вкладки «Диагностика». Пресет игнорируется.")
                            .font(.caption)
                    }
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
                }

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
            }

            Section {
                Button("Сохранить") {
                    appModel.persistSettings()
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct DisplaySettingsTab: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        Form {
            Section("Дисплей") {
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

                Text("MetalFX Spatial — нейронный апскейлер Apple, оптимизирован для игр и работает на Apple Silicon. Без апскейла рендер идёт в нативном размере UVC, что минимально нагружает GPU.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Fullscreen при запуске", isOn: $appModel.fullscreenOnLaunch)
                Toggle("Показывать статистику", isOn: $appModel.showStatsOverlay)

                Button("На весь экран сейчас") {
                    appModel.enterFullscreen()
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AudioSettingsTab: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        Form {
            Section("Аудио устройство") {
                if appModel.audioDevices.isEmpty {
                    Text("Не найдено ни одного audio-устройства. Проверьте, что Cam Link подключён и в Системных настройках macOS → Конфиденциальность → Микрофон разрешён доступ для GameMonitor.")
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

                Button("Обновить список") {
                    appModel.reloadDevices()
                }
            }

            Section("Громкость") {
                Slider(value: Binding(
                    get: { appModel.audio.volume },
                    set: { appModel.audio.volume = $0 }
                ), in: 0...1) {
                    Text("Громкость")
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
        .formStyle(.grouped)
    }
}

private struct DiagnosticsTab: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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
            .padding(8)
        }
        .onAppear {
            appModel.refreshDeviceMetadata()
        }
    }
}

private struct USBInfoCard: View {
    let usb: USBDeviceInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("USB")
                .font(.headline)

            if let usb {
                HStack {
                    Image(systemName: usb.speed.isUSB3 ? "bolt.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(usb.speed.isUSB3 ? .green : .orange)
                    VStack(alignment: .leading) {
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
            } else {
                Text("USB-устройство не найдено в IORegistry. Возможно, карта подключена не как USB-устройство.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct FrameTimingCard: View {
    let samples: [Double]
    let targetFps: Double
    let uvcFps: Double
    let ptsFps: Double
    let sourceSampleDuration: Double          // CMSampleBufferGetDuration в секундах
    let actualMinFrameDuration: Double        // device.activeVideoMinFrameDuration (s)
    let droppedSamples: UInt64

    var body: some View {
        let stats = FrameIntervalStats.compute(samples: samples)
        let durationFps = sourceSampleDuration > 0 ? 1.0 / sourceSampleDuration : 0
        let minDurFps = actualMinFrameDuration > 0 ? 1.0 / actualMinFrameDuration : 0

        return VStack(alignment: .leading, spacing: 8) {
            Text("Тайминг кадров")
                .font(.headline)

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
                    format: "⚠️ После старта activeVideoMinFrameDuration = %.1f мс (~%.0f fps), а должно быть 1/%.0f. AVCaptureSession не приняла нашу настройку даже после повторного set'а — это значит, формат как таковой картой не отдаётся, она UVC-уровневым дескриптором не подтверждает 60.",
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
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
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

        // Wall-clock == PTS == ниже целевого. Источник реально отдаёт меньше.
        if durationFps > 0, abs(durationFps - uvcFps) < 5 {
            return Analysis(
                message: """
                Источник физически отдаёт ~\(Int(uvcFps.rounded())) fps. Sample duration в кадре = ~\(Int(durationFps.rounded())) fps. Это значит, карта/HDMI на входе так и заявляет.

                Что проверить:
                • Switch: Системные настройки → Телевизор → Разрешение и Гц вручную выставить 60 Hz (не «Авто»). При «Авто» Switch может уйти в 50 Hz/PAL по EDID карты.
                • Кабель HDMI: попробуйте другой шнур, особенно если он 1.4/короткий комплектный.
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("UVC-форматы карты")
                    .font(.headline)
                Spacer()
                if appModel.manualFormatID != nil {
                    Button("Сбросить ручной выбор") {
                        appModel.applyManualFormat(nil)
                    }
                    .buttonStyle(.borderless)
                }
            }

            if appModel.availableFormats.isEmpty {
                Text("Список пуст. Подключите карту и нажмите «Старт».")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(appModel.availableFormats) { fmt in
                    formatRow(fmt)
                    Divider()
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func formatRow(_ fmt: FormatDescriptor) -> some View {
        let isActive = appModel.capture.activeFormatDescriptorID == fmt.id
        let isManual = appModel.manualFormatID == fmt.id

        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(fmt.displayLabel)
                        .font(.body.monospacedDigit())
                    if isActive {
                        Text("активный")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .background(Color.green.opacity(0.25), in: Capsule())
                    }
                    if isManual {
                        Text("выбран вручную")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .background(Color.blue.opacity(0.25), in: Capsule())
                    }
                }
                HStack(spacing: 6) {
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
            .buttonStyle(.bordered)
            .disabled(isManual)
        }
        .padding(.vertical, 4)
    }
}
