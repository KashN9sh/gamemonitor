import Foundation

struct CaptureTarget: Equatable {
    let width: Int
    let height: Int
    let frameRate: Double
    let frameRateTolerance: Double

    init(width: Int, height: Int, frameRate: Double, frameRateTolerance: Double = 2) {
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.frameRateTolerance = frameRateTolerance
    }
}

enum VideoCapturePreset: String, CaseIterable, Identifiable, Codable {
    case uhd4k60
    case uhd4k30
    case qhd60
    case qhd30
    case fhd120
    case fhd60

    var id: String { rawValue }

    var title: String {
        switch self {
        case .uhd4k60: return "4K · 60 fps"
        case .uhd4k30: return "4K · 30 fps"
        case .qhd60: return "1440p (2K) · 60 fps"
        case .qhd30: return "1440p (2K) · 30 fps"
        case .fhd120: return "1080p · 120 fps"
        case .fhd60: return "1080p · 60 fps"
        }
    }

    var subtitle: String {
        "Запрос режима UVC на Mac. Разрешение/FPS с HDMI задаёт Switch — карта не меняет сигнал с консоли."
    }

    func describeTarget(_ target: CaptureTarget) -> String {
        "\(target.width)×\(target.height) @ \(Int(target.frameRate)) fps"
    }

    var target: CaptureTarget {
        switch self {
        case .uhd4k60:
            return CaptureTarget(width: 3840, height: 2160, frameRate: 60)
        case .uhd4k30:
            return CaptureTarget(width: 3840, height: 2160, frameRate: 30)
        case .qhd60:
            return CaptureTarget(width: 2560, height: 1440, frameRate: 60)
        case .qhd30:
            return CaptureTarget(width: 2560, height: 1440, frameRate: 30, frameRateTolerance: 1)
        case .fhd120:
            return CaptureTarget(width: 1920, height: 1080, frameRate: 120, frameRateTolerance: 5)
        case .fhd60:
            return CaptureTarget(width: 1920, height: 1080, frameRate: 60)
        }
    }
}
