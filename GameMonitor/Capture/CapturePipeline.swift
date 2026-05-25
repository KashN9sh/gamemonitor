import AppKit
import AVFoundation
import Combine
import CoreMedia
import Foundation

final class CapturePipeline: NSObject, ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var statusMessage = "Ожидание устройства"
    @Published private(set) var activeFormatDescription = "—"
    @Published private(set) var requestedFormatDescription = "—"
    @Published private(set) var mismatchHint: String?
    @Published private(set) var uvcFps: Double = 0      // Wall-clock FPS (наш приёмный темп)
    @Published private(set) var ptsFps: Double = 0      // FPS по PTS-дельтам (что заявляет источник)
    @Published private(set) var configuredFrameRate: Double = 0
    @Published private(set) var lastFrameHostTime: CFTimeInterval = 0
    @Published private(set) var frameIntervalSamples: [Double] = []
    @Published private(set) var activeFormatDescriptorID: String?
    /// Реальный CMSampleBufferDuration в секундах (что карта/драйвер пишут в sampleBuffer).
    @Published private(set) var sourceSampleDuration: Double = 0
    /// Сколько кадров AVFoundation выкинула (didDrop).
    @Published private(set) var droppedSampleCount: UInt64 = 0
    /// activeVideoMinFrameDuration после старта (в секундах). Если ≠ 1/configuredFrameRate, sessionPreset перетер.
    @Published private(set) var actualMinFrameDurationSeconds: Double = 0

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.gamemonitor.capture", qos: .userInteractive)
    private var videoOutput: AVCaptureVideoDataOutput?
    /// Native audio playback напрямую из AVCaptureSession в default output device.
    /// Не идёт через CMSampleBuffer / наш Swift код — поэтому не страдает от throttling
    /// AVCaptureAudioDataOutput, который в фуллскрине доставляет sample buffers пакетами.
    private var audioPreviewOutput: AVCaptureAudioPreviewOutput?
    private var pendingAudioVolume: Float = 1.0
    private var pendingAudioMuted: Bool = false
    private var pendingAudioDeviceID: String?

    private var fpsWindowStart = CFAbsoluteTimeGetCurrent()
    private var uvcFpsWindowFrames: UInt64 = 0
    private var lastSamplePTS: CMTime?
    private var lastSampleHostTime: CFTimeInterval = 0
    private var configuredFPS: Double = 0

    private static let intervalBufferCapacity = 240
    private var ringIntervals: [Double] = []
    private var lastPublishedIntervalsAt: CFTimeInterval = 0

    var onVideoFrame: ((CVPixelBuffer, CMFormatDescription) -> Void)?

    private(set) var hasAudioInput = false
    private(set) var activeTarget = VideoCapturePreset.uhd4k30.target
    @Published private(set) var uvcUnchangedAfterPresetSwitch = false

    private var lastUVCFingerprint: String?
    private var previousTarget: CaptureTarget?

    // Кэш: целевая min frame duration (в секундах) для verify-after-start.
    // AVCaptureSession на macOS любит откатить activeVideoMinFrameDuration в commitConfiguration,
    // и единственный способ закрепить — выставить ещё раз после startRunning().
    private var pendingTargetMinDuration: CMTime?
    private weak var pendingTargetDevice: AVCaptureDevice?

    func configureAndStart(
        device: AVCaptureDevice,
        target: CaptureTarget,
        overrideFormatID: String? = nil,
        audioDevice: AVCaptureDevice?,
        completion: (@MainActor (Bool) -> Void)? = nil
    ) {
        let priorTarget = activeTarget
        let priorFingerprint = lastUVCFingerprint
        activeTarget = target
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.resetMetricsOnQueue()
            let configured = self.configureOnQueue(
                device: device,
                target: target,
                overrideFormatID: overrideFormatID,
                priorTarget: priorTarget,
                priorFingerprint: priorFingerprint,
                audioDevice: audioDevice
            )
            guard configured else {
                DispatchQueue.main.async { completion?(false) }
                return
            }
            guard !self.session.isRunning else {
                DispatchQueue.main.async { completion?(self.hasAudioInput) }
                return
            }
            self.session.startRunning()
            self.reapplyFrameDurationAfterStart()
            let audioEnabled = self.hasAudioInput
            DispatchQueue.main.async {
                self.isRunning = true
                self.statusMessage = "Захват активен"
                completion?(audioEnabled)
            }
        }
    }

    /// AVCaptureSession на macOS периодически перетирает activeVideoMinFrameDuration в
    /// `commitConfiguration` — особенно когда мы выставляем формат, который сама сессия
    /// не считает «своим». Чтобы зафиксировать частоту, перезаписываем frame duration уже
    /// после `startRunning`. Если значение всё равно отличается от целевого — публикуем его,
    /// чтобы overlay показал реальное состояние.
    private func reapplyFrameDurationAfterStart() {
        guard let device = pendingTargetDevice,
              let target = pendingTargetMinDuration,
              CMTimeCompare(target, .zero) > 0 else {
            DispatchQueue.main.async {
                self.actualMinFrameDurationSeconds = 0
            }
            return
        }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            // На случай, если sessionPreset перетёр после commit — выставляем снова.
            device.activeVideoMinFrameDuration = target
            device.activeVideoMaxFrameDuration = target
        } catch {
            // Не можем залочиться — устройство, возможно, уже занято. Не критично.
            print("[CapturePipeline] reapplyFrameDuration: lock failed: \(error)")
        }

        // Прочитать ФАКТИЧЕСКОЕ значение, которое осталось после startRunning + reapply.
        let actualSeconds = CMTimeGetSeconds(device.activeVideoMinFrameDuration)
        DispatchQueue.main.async {
            self.actualMinFrameDurationSeconds = actualSeconds.isFinite ? actualSeconds : 0
        }
    }

    private func resetMetricsOnQueue() {
        ringIntervals.removeAll(keepingCapacity: true)
        lastSamplePTS = nil
        lastSampleHostTime = 0
        uvcFpsWindowFrames = 0
        fpsWindowStart = CFAbsoluteTimeGetCurrent()
        DispatchQueue.main.async {
            self.uvcFps = 0
            self.ptsFps = 0
            self.frameIntervalSamples = []
            self.droppedSampleCount = 0
            self.sourceSampleDuration = 0
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
            DispatchQueue.main.async {
                self.isRunning = false
                self.statusMessage = "Остановлено"
            }
        }
    }

    /// Управление громкостью audio preview output. 0..1, mute = volume = 0.
    /// Пишем сразу из main-потока — AVCaptureAudioPreviewOutput thread-safe для KVC,
    /// а из sessionQueue апдейты иногда теряются если сессия как раз делает re-config.
    func setAudioVolume(_ volume: Float, isMuted: Bool) {
        let target: Float = isMuted ? 0 : max(0, min(1, volume))
        pendingAudioVolume = volume
        pendingAudioMuted = isMuted
        if let preview = audioPreviewOutput {
            preview.volume = target
            print("[CapturePipeline] setAudioVolume: vol=\(volume) muted=\(isMuted) → preview.volume=\(preview.volume)")
        } else {
            print("[CapturePipeline] setAudioVolume: vol=\(volume) muted=\(isMuted) (no preview output yet, cached)")
        }
    }

    /// Целевое устройство audio output. nil = default output (системный).
    func setAudioOutputDevice(uniqueID: String?) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.pendingAudioDeviceID = uniqueID
            self.audioPreviewOutput?.outputDeviceUniqueID = uniqueID
        }
    }

    @discardableResult
    private func configureOnQueue(
        device: AVCaptureDevice,
        target: CaptureTarget,
        overrideFormatID: String?,
        priorTarget: CaptureTarget,
        priorFingerprint: String?,
        audioDevice: AVCaptureDevice?
    ) -> Bool {
        hasAudioInput = false
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        for input in session.inputs { session.removeInput(input) }
        for output in session.outputs { session.removeOutput(output) }

        let selector = FormatSelector(target: target)
        selector.logAllFormats(for: device)

        // На macOS .inputPriority недоступен (iOS-only). Чтобы сессия не перетирала
        // device.activeFormat под свой sessionPreset, добавляем input ПЕРВЫМ,
        // и только ПОСЛЕ этого выставляем activeFormat / activeVideoMinFrameDuration.
        let videoInput: AVCaptureDeviceInput
        do {
            videoInput = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(videoInput) else { throw CaptureError.cannotAddVideoInput }
            session.addInput(videoInput)
        } catch {
            DispatchQueue.main.async {
                self.statusMessage = "Видеовход: \(error.localizedDescription)"
            }
            return false
        }

        var resolvedDescriptorID: String? = nil
        var configuredRate: Double = 0
        var pendingTargetMin: CMTime = .zero

        // 2. Конфигурируем устройство ПОСЛЕ addInput.
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            if let overrideFormatID,
               let overrideFormat = FormatSelector.find(overrideFormatID, in: device) {
                device.activeFormat = overrideFormat
                resolvedDescriptorID = overrideFormatID

                let dims = CMVideoFormatDescriptionGetDimensions(overrideFormat.formatDescription)
                let subType = CMFormatDescriptionGetMediaSubType(overrideFormat.formatDescription)
                let pixelName = FourCC.string(subType)

                let bestRange: AVFrameRateRange? = overrideFormat.videoSupportedFrameRateRanges
                    .max(by: { $0.maxFrameRate < $1.maxFrameRate })
                if let range = bestRange {
                    device.activeVideoMinFrameDuration = range.minFrameDuration
                    device.activeVideoMaxFrameDuration = range.minFrameDuration
                    pendingTargetMin = range.minFrameDuration
                }
                configuredRate = bestRange?.maxFrameRate ?? 0

                self.configuredFPS = configuredRate
                let actual = "\(Int(dims.width))×\(Int(dims.height)) @ \(Int(configuredRate.rounded()))"
                let requested = actual + " (вручную)"
                let fpsRange = selector.actualFrameRateDescription(for: device)
                self.lastUVCFingerprint = "manual-\(overrideFormatID)"
                self.previousTarget = target

                DispatchQueue.main.async {
                    self.configuredFrameRate = configuredRate
                    self.requestedFormatDescription = "Запрос UVC: \(requested)"
                    self.activeFormatDescription =
                        "Карта (UVC): \(actual) \(pixelName)\n\(fpsRange)"
                    self.mismatchHint = nil
                    self.uvcUnchangedAfterPresetSwitch = false
                    self.activeFormatDescriptorID = overrideFormatID
                    if self.statusMessage.hasPrefix("⚠️") || self.statusMessage.contains("не изменился") {
                        self.statusMessage = "Захват активен"
                    }
                }
            } else if let selection = selector.bestFormat(for: device) {
                device.activeFormat = selection.format
                selector.applyFrameDuration(to: device)
                pendingTargetMin = device.activeVideoMinFrameDuration

                self.configuredFPS = selection.frameRate
                configuredRate = selection.frameRate
                let fpsRange = selector.actualFrameRateDescription(for: device)
                let requested = "\(target.width)×\(target.height) @ \(Int(target.frameRate))"
                let actual = "\(selection.width)×\(selection.height) @ \(Int(selection.frameRate.rounded()))"
                let fingerprint = uvcFingerprint(selection: selection)
                self.lastUVCFingerprint = fingerprint
                self.previousTarget = target
                resolvedDescriptorID = formatDescriptorID(format: selection.format, in: device)

                var mismatch = formatMismatch(target: target, selection: selection)
                let presetSwitched = priorTarget != target
                let uvcSame = priorFingerprint != nil && priorFingerprint == fingerprint
                let unchangedNote = presetSwitched && uvcSame
                    ? unchangedPresetMessage(actual: actual)
                    : nil

                if unchangedNote != nil {
                    mismatch = unchangedNote
                }

                let descriptorID = resolvedDescriptorID
                DispatchQueue.main.async {
                    self.configuredFrameRate = configuredRate
                    self.requestedFormatDescription = "Запрос UVC: \(requested)"
                    self.activeFormatDescription =
                        "Карта (UVC): \(actual) \(selection.pixelFormatName)\n\(fpsRange)"
                    self.mismatchHint = mismatch
                    self.uvcUnchangedAfterPresetSwitch = unchangedNote != nil
                    self.activeFormatDescriptorID = descriptorID

                    if let mismatch {
                        self.statusMessage = mismatch
                    } else if self.statusMessage.hasPrefix("⚠️") || self.statusMessage.contains("не изменился") {
                        self.statusMessage = "Захват активен"
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.requestedFormatDescription = "Запрос UVC: \(target.width)×\(target.height) @ \(Int(target.frameRate))"
                    self.activeFormatDescription = "Карта: режим не найден"
                    self.mismatchHint = "Карта не отдаёт этот UVC-режим. Смените вывод на Switch или другой пресет."
                    self.statusMessage = self.mismatchHint ?? "Ошибка формата"
                    self.activeFormatDescriptorID = nil
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.statusMessage = "Ошибка конфигурации: \(error.localizedDescription)"
            }
            return false
        }

        // Сохраняем целевую min duration, чтобы verify+reapply сделать после startRunning.
        // Само значение activeMinFrameDuration публикуется уже ИЗ reapplyFrameDurationAfterStart.
        pendingTargetDevice = device
        pendingTargetMinDuration = pendingTargetMin
        let _ = configuredRate

        // 3. Output добавляем последним.
        let videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
        ]
        videoDataOutput.setSampleBufferDelegate(self, queue: sessionQueue)

        guard session.canAddOutput(videoDataOutput) else {
            DispatchQueue.main.async { self.statusMessage = "Не удалось добавить видеовыход" }
            return false
        }
        session.addOutput(videoDataOutput)
        videoOutput = videoDataOutput

        if let audioDevice {
            do {
                let audioInput = try AVCaptureDeviceInput(device: audioDevice)
                if session.canAddInput(audioInput) {
                    session.addInput(audioInput)
                    // AVCaptureAudioPreviewOutput — system audio play напрямую из capture
                    // session в текущий default output device. macOS управляет routing'ом
                    // и не throttle-ит этот путь в фуллскрине, в отличие от
                    // AVCaptureAudioDataOutput → CMSampleBuffer → AVAudioEngine.
                    let preview = AVCaptureAudioPreviewOutput()
                    preview.outputDeviceUniqueID = pendingAudioDeviceID
                    preview.volume = pendingAudioMuted ? 0 : pendingAudioVolume
                    if session.canAddOutput(preview) {
                        session.addOutput(preview)
                        audioPreviewOutput = preview
                        hasAudioInput = true
                        print("[CapturePipeline] Audio input attached (preview output): \(audioDevice.localizedName), vol=\(preview.volume)")
                    } else {
                        print("[CapturePipeline] canAddOutput(AudioPreview) = false for \(audioDevice.localizedName)")
                    }
                } else {
                    print("[CapturePipeline] canAddInput failed for audio device \(audioDevice.localizedName)")
                }
            } catch {
                print("[CapturePipeline] Audio input error for \(audioDevice.localizedName): \(error)")
            }
        } else {
            print("[CapturePipeline] No audio device passed in.")
        }

        DispatchQueue.main.async {
            self.statusMessage = "Готово: \(device.localizedName)"
        }
        return true
    }

    private func uvcFingerprint(selection: FormatSelector.Selection) -> String {
        "\(selection.width)x\(selection.height)@\(Int(selection.frameRate.rounded()))-\(selection.pixelFormatName)"
    }

    private func formatDescriptorID(format: AVCaptureDevice.Format, in device: AVCaptureDevice) -> String? {
        for (index, candidate) in device.formats.enumerated() where candidate === format {
            let dims = CMVideoFormatDescriptionGetDimensions(candidate.formatDescription)
            let subType = CMFormatDescriptionGetMediaSubType(candidate.formatDescription)
            return "\(index)-\(Int(dims.width))x\(Int(dims.height))-\(FourCC.string(subType))"
        }
        return nil
    }

    private func unchangedPresetMessage(actual: String) -> String {
        "⚠️ Пресет в приложении сменился, но UVC карты не изменился (\(actual)). Switch в «Авто» — задайте 1440p/1080p/4K вручную на консоли, пресет здесь не переключит HDMI."
    }

    private func formatMismatch(target: CaptureTarget, selection: FormatSelector.Selection) -> String? {
        let widthOK = selection.width == target.width
        let heightOK = selection.height == target.height
        let fpsOK = abs(selection.frameRate - target.frameRate) <= target.frameRateTolerance + 1

        if widthOK && heightOK && fpsOK { return nil }

        var parts: [String] = []
        if !widthOK || !heightOK {
            parts.append("разрешение \(selection.width)×\(selection.height) вместо \(target.width)×\(target.height)")
        }
        if !fpsOK {
            parts.append("≈\(Int(selection.frameRate.rounded())) fps вместо \(Int(target.frameRate))")
        }

        return "⚠️ Switch/HDMI управляет картинкой. Карта отдаёт: \(parts.joined(separator: ", ")). Настройте Switch, пресет здесь только для UVC."
    }
}

extension CapturePipeline: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        if output is AVCaptureVideoDataOutput {
            handleVideoSample(sampleBuffer)
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard output is AVCaptureVideoDataOutput else { return }
        DispatchQueue.main.async {
            self.droppedSampleCount &+= 1
        }
    }

    private func handleVideoSample(_ sampleBuffer: CMSampleBuffer) {
        let hostTime = CFAbsoluteTimeGetCurrent()
        uvcFpsWindowFrames += 1

        if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
           let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) {
            onVideoFrame?(pixelBuffer, formatDescription)
        }

        // Wall-clock interval ring buffer: то, что мы реально получаем.
        if lastSampleHostTime > 0 {
            let interval = hostTime - lastSampleHostTime
            if interval > 0.001, interval < 1.0 {
                if ringIntervals.count >= Self.intervalBufferCapacity {
                    ringIntervals.removeFirst(ringIntervals.count - Self.intervalBufferCapacity + 1)
                }
                ringIntervals.append(interval)
            }
        }
        lastSampleHostTime = hostTime

        // PTS-based FPS — то, что заявляет источник.
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if lastSamplePTS != nil, pts.isValid, lastSamplePTS!.isValid {
            let delta = CMTimeGetSeconds(CMTimeSubtract(pts, lastSamplePTS!))
            if delta > 0.001, delta < 0.2 {
                let instantPTSFPS = 1.0 / delta
                DispatchQueue.main.async {
                    self.ptsFps = self.ptsFps * 0.85 + instantPTSFPS * 0.15
                }
            }
        }
        if pts.isValid { lastSamplePTS = pts }

        // Sample duration — что карта/драйвер пишут в sampleBuffer.
        // Если duration = 1/25, источник заявляет 25 fps на уровне UVC payload.
        let bufferDuration = CMSampleBufferGetDuration(sampleBuffer)
        let durationSec = CMTimeGetSeconds(bufferDuration)

        let elapsed = hostTime - fpsWindowStart
        if elapsed >= 0.5 {
            let measuredUVC = Double(uvcFpsWindowFrames) / elapsed
            uvcFpsWindowFrames = 0
            fpsWindowStart = hostTime

            let snapshot = ringIntervals
            let publish = (hostTime - lastPublishedIntervalsAt) > 0.2
            if publish { lastPublishedIntervalsAt = hostTime }

            let publishedDuration = durationSec.isFinite && durationSec > 0 ? durationSec : 0

            DispatchQueue.main.async {
                self.lastFrameHostTime = hostTime
                self.uvcFps = measuredUVC
                if publishedDuration > 0 {
                    self.sourceSampleDuration = publishedDuration
                }
                if publish {
                    self.frameIntervalSamples = snapshot
                }
            }
        }
    }
}

enum CaptureError: LocalizedError {
    case cannotAddVideoInput

    var errorDescription: String? {
        switch self {
        case .cannotAddVideoInput:
            return "Не удалось подключить видеоустройство"
        }
    }
}
