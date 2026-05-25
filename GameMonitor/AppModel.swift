import AVFoundation
import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    let capture = CapturePipeline()
    let audio = AudioPipeline()
    let renderer: MetalRenderer?

    @Published var devices: [CaptureDeviceInfo] = []
    @Published var audioDevices: [CaptureDeviceInfo] = []
    @Published var screens: [ScreenOption] = []
    @Published var selectedDeviceID: String?
    @Published var selectedAudioDeviceID: String? = AppSettings.selectedAudioDeviceID
    @Published var selectedScreenID: Int?
    @Published var fullscreenOnLaunch: Bool = AppSettings.fullscreenOnLaunch
    @Published var showStatsOverlay: Bool = AppSettings.showStatsOverlay
    @Published var videoPreset: VideoCapturePreset = AppSettings.videoPreset
    @Published var upscaleMode: UpscaleMode = AppSettings.upscaleMode
    @Published var manualFormatID: String? = AppSettings.manualFormatID
    @Published var availableFormats: [FormatDescriptor] = []
    @Published var usbInfo: USBDeviceInfo?
    @Published var errorMessage: String?

    @Published private(set) var presentedFps: Double = 0
    @Published private(set) var droppedFrames: UInt64 = 0
    @Published private(set) var gpuMilliseconds: Double = 0
    @Published private(set) var rendererAvailable = true
    @Published private(set) var isFullscreen: Bool = false

    private weak var mainWindow: NSWindow?
    private var fullscreenObservers: [NSObjectProtocol] = []

    init() {
        let renderer = MetalRenderer()
        self.renderer = renderer
        if renderer == nil {
            errorMessage = "Не удалось инициализировать Metal на этом Mac."
        }

        selectedDeviceID = AppSettings.selectedDeviceID
        selectedScreenID = AppSettings.selectedScreenID
        reloadDevices()
        reloadScreens()

        rendererAvailable = renderer != nil
        renderer?.setUpscaleMode(upscaleMode)
        renderer?.statsCallback = { [weak self] stats in
            DispatchQueue.main.async {
                guard let self else { return }
                self.presentedFps = stats.presentedFps
                self.droppedFrames = stats.droppedFrames
                self.gpuMilliseconds = stats.gpuMilliseconds
            }
        }

        // Audio теперь играется через AVCaptureAudioPreviewOutput напрямую из capture
        // session в default audio device. AudioPipeline — тонкая обёртка над volume/mute,
        // которая пушит изменения в capture's preview output.
        audio.bind(capture: capture)

        capture.onVideoFrame = { [weak self] pixelBuffer, formatDescription in
            self?.renderer?.render(pixelBuffer: pixelBuffer, formatDescription: formatDescription)
        }
    }

    deinit {
        for observer in fullscreenObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func reloadDevices() {
        devices = DeviceDiscovery.videoDevices()
        audioDevices = DeviceDiscovery.audioDevices()
        if selectedDeviceID == nil {
            selectedDeviceID = DeviceDiscovery.preferredVideoDevice(savedID: nil)?.id
        }
        refreshDeviceMetadata()
    }

    /// Обновить usbInfo и availableFormats для выбранного устройства.
    func refreshDeviceMetadata() {
        guard let deviceInfo = devices.first(where: { $0.id == selectedDeviceID })
            ?? DeviceDiscovery.preferredVideoDevice(savedID: selectedDeviceID) else {
            availableFormats = []
            usbInfo = nil
            return
        }
        availableFormats = FormatSelector.describeAllFormats(for: deviceInfo.device)
        usbInfo = USBDeviceLookup.info(matchingDeviceName: deviceInfo.name)
    }

    func reloadScreens() {
        screens = ScreenSelector.allScreens()
        if selectedScreenID == nil {
            if let screen = ScreenSelector.preferredScreen(savedID: nil),
               let index = screens.firstIndex(where: { $0.screen === screen }) {
                selectedScreenID = index
            } else {
                selectedScreenID = 0
            }
        }
    }

    func start() {
        requestCapturePermissions()

        guard let deviceInfo = devices.first(where: { $0.id == selectedDeviceID })
            ?? DeviceDiscovery.preferredVideoDevice(savedID: selectedDeviceID)
        else {
            errorMessage = "Карта захвата не найдена. Подключите Cam Link по USB."
            return
        }

        selectedDeviceID = deviceInfo.id
        AppSettings.selectedDeviceID = deviceInfo.id
        AppSettings.upscaleMode = upscaleMode
        AppSettings.manualFormatID = manualFormatID

        AppSettings.selectedAudioDeviceID = selectedAudioDeviceID
        audioDevices = DeviceDiscovery.audioDevices()
        let audioDevice = DeviceDiscovery.audioDevice(
            matchingVideoName: deviceInfo.name,
            savedID: selectedAudioDeviceID
        )
        if let audioDevice {
            selectedAudioDeviceID = audioDevice.uniqueID
        }
        let launchFullscreen = fullscreenOnLaunch

        renderer?.setUpscaleMode(upscaleMode)

        availableFormats = FormatSelector.describeAllFormats(for: deviceInfo.device)
        usbInfo = USBDeviceLookup.info(matchingDeviceName: deviceInfo.name)

        capture.configureAndStart(
            device: deviceInfo.device,
            target: videoPreset.target,
            overrideFormatID: manualFormatID,
            audioDevice: audioDevice
        ) { [weak self] hasAudio in
            guard let self else { return }
            if hasAudio {
                self.audio.start()
            } else {
                self.audio.statusMessage = "Аудиоустройство не найдено"
            }
            if launchFullscreen {
                self.enterFullscreen()
            }
        }
    }

    func stop() {
        capture.stop()
        audio.stop()
        exitFullscreen()
    }

    /// Регистрирует ссылку на main window. Вызывается из ContentView через `WindowAccessor`,
    /// один раз. Настраивает collectionBehavior и подписывается на enter/exit fullscreen
    /// notifications, чтобы держать `isFullscreen` в актуальном состоянии.
    func registerMainWindow(_ window: NSWindow) {
        guard mainWindow !== window else { return }
        mainWindow = window
        // Без .fullScreenPrimary окно не сможет уйти в native fullscreen Space.
        window.collectionBehavior.insert(.fullScreenPrimary)
        // Media-app chrome: контент идёт под title bar, без видимого заголовка,
        // чёрный фон под плеер. Liquid Glass elements рендерятся поверх.
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        // ВАЖНО: isMovableByWindowBackground = false. Иначе AppKit перехватывает
        // mouse-down где попало (включая glass-капсулу с Slider'ом) и таскает окно
        // вместо thumb'а. Окно всё равно можно двигать за прозрачную title-bar зону
        // сверху (~28pt) — она здесь сохраняется.
        window.isMovableByWindowBackground = false
        window.backgroundColor = .black
        window.minSize = NSSize(width: 960, height: 540)
        window.setFrameAutosaveName("GameMonitorMainWindow")

        for observer in fullscreenObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        fullscreenObservers.removeAll()

        let center = NotificationCenter.default
        let onEnter = center.addObserver(
            forName: NSWindow.didEnterFullScreenNotification,
            object: window,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.isFullscreen = true }
        }
        let onExit = center.addObserver(
            forName: NSWindow.didExitFullScreenNotification,
            object: window,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.isFullscreen = false }
        }
        fullscreenObservers = [onEnter, onExit]
    }

    func enterFullscreen() {
        guard let window = mainWindow else { return }
        guard !window.styleMask.contains(.fullScreen) else { return }

        // Перенести окно на выбранный экран до toggleFullScreen — иначе native fullscreen
        // запустится на том экране, где окно сейчас.
        if let screen = ScreenSelector.preferredScreen(savedID: selectedScreenID),
           window.screen !== screen {
            let frame = NSRect(
                x: screen.frame.midX - 480,
                y: screen.frame.midY - 270,
                width: 960,
                height: 540
            )
            window.setFrame(frame, display: true)
        }
        AppSettings.selectedScreenID = selectedScreenID

        // Никакого audio.refresh() — native fullscreen routing не меняет.
        // Если macOS реально пере-выбирает device, прилетит AVAudioEngineConfigurationChange,
        // и AudioPipeline отработает сам.
        window.toggleFullScreen(nil)
    }

    func exitFullscreen() {
        guard let window = mainWindow else { return }
        if window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
    }

    private func requestCapturePermissions() {
        AVCaptureDevice.requestAccess(for: .video) { _ in }
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
    }

    func applyPresetAndRestart() {
        // Смена пресета сбрасывает ручной выбор формата.
        manualFormatID = nil
        AppSettings.manualFormatID = nil
        AppSettings.videoPreset = videoPreset
        AppSettings.upscaleMode = upscaleMode
        renderer?.setUpscaleMode(upscaleMode)
        guard capture.isRunning else { return }
        stop()
        start()
    }

    /// Выбрать формат вручную (из вкладки Диагностика). Перезапускает захват.
    func applyManualFormat(_ id: String?) {
        manualFormatID = id
        AppSettings.manualFormatID = id
        guard capture.isRunning else { return }
        stop()
        start()
    }

    func applyUpscaleMode() {
        AppSettings.upscaleMode = upscaleMode
        renderer?.setUpscaleMode(upscaleMode)
    }

    func persistSettings() {
        AppSettings.selectedDeviceID = selectedDeviceID
        AppSettings.selectedAudioDeviceID = selectedAudioDeviceID
        AppSettings.selectedScreenID = selectedScreenID
        AppSettings.fullscreenOnLaunch = fullscreenOnLaunch
        AppSettings.showStatsOverlay = showStatsOverlay
        AppSettings.videoPreset = videoPreset
        AppSettings.upscaleMode = upscaleMode
        AppSettings.manualFormatID = manualFormatID
        AppSettings.volume = audio.volume
        AppSettings.isMuted = audio.isMuted
    }
}
