import Foundation

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

    static var showStatsOverlay: Bool {
        get { defaults.object(forKey: "showStatsOverlay") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showStatsOverlay") }
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
