import Foundation

/// Три режима HUD-а со статистикой поверх плеера.
/// - `.off` — ничего не рисуем (чистая картинка).
/// - `.compact` — крупная полупрозрачная цифра FPS в углу, в духе iPhone Lock Screen.
/// - `.full` — подробная glass-карточка со всеми метриками (UVC/PTS/GPU и т.д.).
enum StatsDisplayMode: String, CaseIterable, Identifiable {
    case off
    case compact
    case full

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Скрыть"
        case .compact: return "Только FPS"
        case .full: return "Подробная"
        }
    }

    var systemImage: String {
        switch self {
        case .off: return "rectangle"
        case .compact: return "speedometer"
        case .full: return "chart.bar.doc.horizontal"
        }
    }

    /// Циклический шаг для горячей клавиши — off → compact → full → off.
    var next: StatsDisplayMode {
        switch self {
        case .off: return .compact
        case .compact: return .full
        case .full: return .off
        }
    }
}

enum AppSettings {
    private static let defaults = UserDefaults.standard

    static var selectedDeviceID: String? {
        get { defaults.string(forKey: "selectedDeviceID") }
        set { defaults.set(newValue, forKey: "selectedDeviceID") }
    }

    static var selectedAudioDeviceID: String? {
        get { defaults.string(forKey: "selectedAudioDeviceID") }
        set {
            if let newValue {
                defaults.set(newValue, forKey: "selectedAudioDeviceID")
            } else {
                defaults.removeObject(forKey: "selectedAudioDeviceID")
            }
        }
    }

    static var selectedScreenID: Int? {
        get {
            let value = defaults.integer(forKey: "selectedScreenID")
            return defaults.object(forKey: "selectedScreenID") == nil ? nil : value
        }
        set {
            if let newValue {
                defaults.set(newValue, forKey: "selectedScreenID")
            } else {
                defaults.removeObject(forKey: "selectedScreenID")
            }
        }
    }

    static var fullscreenOnLaunch: Bool {
        get { defaults.object(forKey: "fullscreenOnLaunch") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "fullscreenOnLaunch") }
    }

    static var volume: Float {
        get {
            if defaults.object(forKey: "volume") == nil { return 1.0 }
            return defaults.float(forKey: "volume")
        }
        set { defaults.set(newValue, forKey: "volume") }
    }

    static var isMuted: Bool {
        get { defaults.bool(forKey: "isMuted") }
        set { defaults.set(newValue, forKey: "isMuted") }
    }

    /// Какой HUD со статистикой рисуем поверх плеера.
    /// Миграция: если есть только старый булевый ключ `showStatsOverlay`,
    /// true → `.compact` (новый «лёгкий» вариант), false → `.off`.
    static var statsDisplayMode: StatsDisplayMode {
        get {
            if let raw = defaults.string(forKey: "statsDisplayMode"),
               let mode = StatsDisplayMode(rawValue: raw) {
                return mode
            }
            if defaults.object(forKey: "showStatsOverlay") != nil {
                return defaults.bool(forKey: "showStatsOverlay") ? .compact : .off
            }
            return .compact
        }
        set { defaults.set(newValue.rawValue, forKey: "statsDisplayMode") }
    }

    static var upscaleMode: UpscaleMode {
        get {
            guard let raw = defaults.string(forKey: "upscaleMode"),
                  let mode = UpscaleMode(rawValue: raw) else {
                return .spatial
            }
            return mode
        }
        set { defaults.set(newValue.rawValue, forKey: "upscaleMode") }
    }

    static var videoPreset: VideoCapturePreset {
        get {
            guard let raw = defaults.string(forKey: "videoPreset"),
                  let preset = VideoCapturePreset(rawValue: raw) else {
                return .uhd4k30
            }
            return preset
        }
        set { defaults.set(newValue.rawValue, forKey: "videoPreset") }
    }

    /// ID UVC-формата выбранного вручную из вкладки Диагностика.
    /// Если задан — игнорируем videoPreset и подменяем activeFormat напрямую.
    static var manualFormatID: String? {
        get { defaults.string(forKey: "manualFormatID") }
        set {
            if let newValue {
                defaults.set(newValue, forKey: "manualFormatID")
            } else {
                defaults.removeObject(forKey: "manualFormatID")
            }
        }
    }
}
