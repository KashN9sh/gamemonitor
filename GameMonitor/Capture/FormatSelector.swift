import AVFoundation
import CoreMedia

struct FormatSelector {
    let target: CaptureTarget

    struct Selection: Sendable {
        let format: AVCaptureDevice.Format
        let width: Int
        let height: Int
        let frameRate: Double
        let pixelFormatName: String
        let score: Int
    }

    func bestFormat(for device: AVCaptureDevice) -> Selection? {
        if let match = bestFormatMatching(target: target, device: device) {
            return match
        }

        // 60 fps недоступен на карте — пробуем тот же размер минимум 30 fps (не 25 PAL)
        if target.frameRate >= 55 {
            let fallback = CaptureTarget(
                width: target.width,
                height: target.height,
                frameRate: 30,
                frameRateTolerance: 1
            )
            return bestFormatMatching(target: fallback, device: device)
        }

        return nil
    }

    private func bestFormatMatching(target: CaptureTarget, device: AVCaptureDevice) -> Selection? {
        var best: Selection?
        let selector = FormatSelector(target: target)

        for format in device.formats {
            let desc = format.formatDescription
            let dims = CMVideoFormatDescriptionGetDimensions(desc)
            let width = Int(dims.width)
            let height = Int(dims.height)

            guard selector.supportsTargetFrameRate(format) else { continue }

            let fps = selector.preferredFrameRate(for: format)
            var score = selector.scoreFormat(width: width, height: height, subType: CMFormatDescriptionGetMediaSubType(desc), fps: fps)

            if format.videoSupportedFrameRateRanges.contains(where: {
                selector.isFixedFrameRateRange($0) && selector.rangeMatchesTargetFPS($0, targetFPS: target.frameRate)
            }) {
                score += 500
            }

            let candidate = Selection(
                format: format,
                width: width,
                height: height,
                frameRate: fps,
                pixelFormatName: fourCCString(CMFormatDescriptionGetMediaSubType(desc)),
                score: score
            )

            if let best, best.score >= candidate.score { continue }
            best = candidate
        }

        return best
    }

    func applyFrameDuration(to device: AVCaptureDevice) {
        let ranges = device.activeFormat.videoSupportedFrameRateRanges
        guard !ranges.isEmpty else { return }

        if let fixed = bestFixedRange(in: ranges, targetFPS: target.frameRate) {
            device.activeVideoMinFrameDuration = fixed.minFrameDuration
            device.activeVideoMaxFrameDuration = fixed.maxFrameDuration
            return
        }

        // Переменный диапазон: для 60 fps — кратчайший интервал (макс. FPS), не 25 PAL
        if target.frameRate >= 55,
           let range = ranges.max(by: { $0.maxFrameRate < $1.maxFrameRate }),
           range.maxFrameRate >= target.frameRate - target.frameRateTolerance {
            device.activeVideoMinFrameDuration = range.minFrameDuration
            device.activeVideoMaxFrameDuration = range.minFrameDuration
            return
        }

        // Для 30 fps — ищем фикс. 30; иначе не трогаем (лучше дефолт, чем NSException)
        if target.frameRate >= 29, target.frameRate <= 31,
           let fixed30 = bestFixedRange(in: ranges, targetFPS: 30) {
            device.activeVideoMinFrameDuration = fixed30.minFrameDuration
            device.activeVideoMaxFrameDuration = fixed30.maxFrameDuration
        }
    }

    func actualFrameRateDescription(for device: AVCaptureDevice) -> String {
        let ranges = device.activeFormat.videoSupportedFrameRateRanges
        guard !ranges.isEmpty else { return "диапазоны FPS: ?" }

        let minDur = CMTimeGetSeconds(device.activeVideoMinFrameDuration)
        let maxDur = CMTimeGetSeconds(device.activeVideoMaxFrameDuration)
        let maxFPS = minDur > 0 ? 1.0 / minDur : 0
        let minFPS = maxDur > 0 ? 1.0 / maxDur : 0
        let interval: String
        if abs(maxFPS - minFPS) < 0.5 {
            interval = String(format: "фикс. %.0f fps", maxFPS)
        } else {
            interval = String(format: "от %.0f до %.0f fps", minFPS, maxFPS)
        }

        let supported = ranges
            .map { String(format: "%.0f–%.0f", $0.minFrameRate, $0.maxFrameRate) }
            .joined(separator: ", ")
        return "интервал UVC: \(interval) | режимы [\(supported)]"
    }

    func logAllFormats(for device: AVCaptureDevice) {
        print("[FormatSelector] Цель: \(target.width)x\(target.height) @ \(Int(target.frameRate))")
        print("[FormatSelector] Formats for \(device.localizedName):")
        for format in device.formats {
            let desc = format.formatDescription
            let dims = CMVideoFormatDescriptionGetDimensions(desc)
            let subType = CMFormatDescriptionGetMediaSubType(desc)
            let fpsRanges = format.videoSupportedFrameRateRanges
            let fpsText = fpsRanges
                .map { String(format: "%.1f–%.1f", $0.minFrameRate, $0.maxFrameRate) }
                .joined(separator: ", ")
            print("  \(Int(dims.width))x\(Int(dims.height)) \(fourCCString(subType)) fps [\(fpsText)]")
        }
    }

    private func preferredFrameRate(for format: AVCaptureDevice.Format) -> Double {
        let ranges = format.videoSupportedFrameRateRanges.filter {
            rangeMatchesTargetFPS($0, targetFPS: target.frameRate)
        }
        guard !ranges.isEmpty else {
            return format.videoSupportedFrameRateRanges.first?.maxFrameRate ?? 0
        }

        if let fixed = bestFixedRange(in: ranges, targetFPS: target.frameRate) {
            return fixed.maxFrameRate
        }

        return ranges.max(by: { $0.maxFrameRate < $1.maxFrameRate })?.maxFrameRate ?? target.frameRate
    }

    private func bestFixedRange(in ranges: [AVFrameRateRange], targetFPS: Double) -> AVFrameRateRange? {
        let fixed = ranges.filter(isFixedFrameRateRange)
        guard !fixed.isEmpty else { return nil }

        let ntscPreferred: [Double]
        if targetFPS >= 55 {
            ntscPreferred = [60, 59.94, 50, 48, 30, 29.97, 25, 24]
        } else if targetFPS >= 29 {
            ntscPreferred = [30, 29.97, 60, 59.94, 50, 25, 24]
        } else {
            ntscPreferred = [targetFPS, 120, 60, 59.94, 30, 29.97, 50, 25]
        }

        for preferred in ntscPreferred {
            if let match = fixed.first(where: { abs($0.maxFrameRate - preferred) < 0.8 }) {
                return match
            }
        }

        return fixed.min(by: { abs($0.maxFrameRate - targetFPS) < abs($1.maxFrameRate - targetFPS) })
    }

    private func supportsTargetFrameRate(_ format: AVCaptureDevice.Format) -> Bool {
        format.videoSupportedFrameRateRanges.contains { range in
            rangeMatchesTargetFPS(range, targetFPS: target.frameRate)
        }
    }

    private func scoreFormat(width: Int, height: Int, subType: FourCharCode, fps: Double) -> Int {
        var score = pixelFormatScore(subType)
        score -= abs(width - target.width) / 4 + abs(height - target.height) / 4
        score -= Int(abs(fps - target.frameRate) * 80)

        if width == target.width && height == target.height {
            score += 10_000
        }

        // Не брать 25 fps, если целимся в 30/60 (PAL при 60 Hz дисплее)
        if target.frameRate >= 29, fps > 0, fps < 28 {
            score -= 8_000
        }
        if target.frameRate >= 55, fps > 0, fps < 50 {
            score -= 8_000
        }

        if abs(fps - target.frameRate) < 1 {
            score += 2_000
        }

        return score
    }

    private func isFixedFrameRateRange(_ range: AVFrameRateRange) -> Bool {
        abs(range.minFrameRate - range.maxFrameRate) < 0.5
    }

    private func rangeMatchesTargetFPS(_ range: AVFrameRateRange, targetFPS: Double) -> Bool {
        range.maxFrameRate >= targetFPS - target.frameRateTolerance
            && range.minFrameRate <= targetFPS + target.frameRateTolerance
    }

    private func pixelFormatScore(_ subType: FourCharCode) -> Int {
        switch subType {
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
             kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            return 5000
        case kCVPixelFormatType_420YpCbCr8Planar,
             kCVPixelFormatType_420YpCbCr8PlanarFullRange:
            return 4800
        case kCVPixelFormatType_422YpCbCr8:
            return 4600
        case kCVPixelFormatType_32BGRA:
            return 4400
        default:
            let text = fourCCString(subType)
            if text.contains("MJPG") || text.contains("jpeg") || subType == kCMVideoCodecType_JPEG {
                return 2000
            }
            return 1000
        }
    }

    private func fourCCString(_ code: FourCharCode) -> String {
        FourCC.string(code)
    }
}

enum FourCC {
    static func string(_ code: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xff),
            UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff),
            UInt8(code & 0xff),
        ]
        return String(bytes: bytes, encoding: .macOSRoman) ?? "????"
    }
}

struct FrameRateRangeDescriptor: Hashable {
    let minFps: Double
    let maxFps: Double

    var isFixed: Bool { abs(maxFps - minFps) < 0.5 }

    var label: String {
        if isFixed {
            return String(format: "%.0f", maxFps)
        }
        return String(format: "%.0f-%.0f", minFps, maxFps)
    }
}

struct FormatDescriptor: Identifiable, Hashable {
    let id: String
    let width: Int
    let height: Int
    let pixelFormat: FourCharCode
    let pixelFormatName: String
    let frameRateRanges: [FrameRateRangeDescriptor]
    let isMetalCompatibleNV12: Bool
    let isMJPEG: Bool

    static func == (lhs: FormatDescriptor, rhs: FormatDescriptor) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var maxFps: Double {
        frameRateRanges.map(\.maxFps).max() ?? 0
    }

    var supports60: Bool {
        frameRateRanges.contains { $0.maxFps >= 59 }
    }

    var supports30: Bool {
        frameRateRanges.contains { $0.maxFps >= 29 && $0.minFps <= 31 }
    }

    var fpsLabel: String {
        let parts = frameRateRanges.map(\.label)
        return parts.joined(separator: "/")
    }

    var displayLabel: String {
        let resolution = "\(width)×\(height)"
        return "\(resolution) · \(pixelFormatName) · \(fpsLabel) fps"
    }
}

extension FormatSelector {
    /// Полный список форматов устройства для UI/диагностики.
    static func describeAllFormats(for device: AVCaptureDevice) -> [FormatDescriptor] {
        device.formats.enumerated().map { index, format in
            let desc = format.formatDescription
            let dims = CMVideoFormatDescriptionGetDimensions(desc)
            let subType = CMFormatDescriptionGetMediaSubType(desc)
            let fourCC = FourCC.string(subType)

            let ranges: [FrameRateRangeDescriptor] = format.videoSupportedFrameRateRanges.map {
                FrameRateRangeDescriptor(minFps: $0.minFrameRate, maxFps: $0.maxFrameRate)
            }

            let isNV12 = subType == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                || subType == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            let isMJPEG = fourCC.uppercased().contains("MJPG")
                || fourCC.uppercased().contains("JPEG")
                || subType == kCMVideoCodecType_JPEG

            return FormatDescriptor(
                id: "\(index)-\(Int(dims.width))x\(Int(dims.height))-\(fourCC)",
                width: Int(dims.width),
                height: Int(dims.height),
                pixelFormat: subType,
                pixelFormatName: fourCC,
                frameRateRanges: ranges.sorted(by: { $0.maxFps < $1.maxFps }),
                isMetalCompatibleNV12: isNV12,
                isMJPEG: isMJPEG
            )
        }
    }

    /// Найти AVCaptureDevice.Format по FormatDescriptor.id.
    static func find(_ descriptorID: String, in device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        for (index, format) in device.formats.enumerated() {
            let desc = format.formatDescription
            let dims = CMVideoFormatDescriptionGetDimensions(desc)
            let subType = CMFormatDescriptionGetMediaSubType(desc)
            let fourCC = FourCC.string(subType)
            let candidateID = "\(index)-\(Int(dims.width))x\(Int(dims.height))-\(fourCC)"
            if candidateID == descriptorID {
                return format
            }
        }
        return nil
    }
}
