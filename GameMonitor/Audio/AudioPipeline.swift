import Foundation

/// Тонкая обёртка над AVCaptureAudioPreviewOutput. Хранит volume/isMuted/output device,
/// публикует их в @Published для UI. Реальное воспроизведение делает AVCaptureSession
/// через preview output (см. CapturePipeline) — это native path macOS, который не
/// страдает от throttling в фуллскрине.
///
/// Раньше тут был полноценный AVAudioEngine + AVAudioPlayerNode + AVAudioConverter
/// поверх CMSampleBuffer от AVCaptureAudioDataOutput. На практике AVCaptureSession
/// доставляла audio sample buffers с задержками и пакетами — особенно когда наше окно
/// уходило в native fullscreen Space (samples просто переставали идти). Преview output
/// эту проблему обходит полностью.
final class AudioPipeline: ObservableObject {
    @Published var volume: Float = AppSettings.volume {
        didSet {
            AppSettings.volume = volume
            applyToCapture()
        }
    }

    @Published var isMuted: Bool = AppSettings.isMuted {
        didSet {
            AppSettings.isMuted = isMuted
            applyToCapture()
        }
    }

    @Published var statusMessage = "Аудио выкл."

    private weak var capture: CapturePipeline?

    /// Прицепить обёртку к capture pipeline. Вызывается один раз при инициализации
    /// AppModel. После этого изменения volume/isMuted сразу пушатся в preview output.
    func bind(capture: CapturePipeline) {
        self.capture = capture
        applyToCapture()
    }

    /// Вызывается после успешного старта capture. Помечает аудио как активное в UI.
    func start() {
        applyToCapture()
        publishStatus("Аудио активно")
    }

    func stop() {
        publishStatus("Аудио остановлено")
    }

    /// Совместимость со старым API. Native preview output не нуждается в refresh —
    /// macOS сам управляет routing'ом. Метод оставлен пустым на случай ручного refresh
    /// из Settings (можно дёрнуть commit volume).
    func refresh() {
        applyToCapture()
    }

    private func applyToCapture() {
        capture?.setAudioVolume(volume, isMuted: isMuted)
    }

    private func publishStatus(_ message: String) {
        if Thread.isMainThread {
            self.statusMessage = message
        } else {
            DispatchQueue.main.async { self.statusMessage = message }
        }
    }
}
