import AVFoundation

struct CaptureDeviceInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let device: AVCaptureDevice

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: CaptureDeviceInfo, rhs: CaptureDeviceInfo) -> Bool {
        lhs.id == rhs.id
    }
}

enum DeviceDiscovery {
    private static let preferredNameTokens = [
        "cam link", "camlink", "ezcap", "capture", "hdmi",
    ]

    static func videoDevices() -> [CaptureDeviceInfo] {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external, .builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        )
        return session.devices.map {
            CaptureDeviceInfo(id: $0.uniqueID, name: $0.localizedName, device: $0)
        }
    }

    static func preferredVideoDevice(savedID: String?) -> CaptureDeviceInfo? {
        let devices = videoDevices()
        if let savedID, let saved = devices.first(where: { $0.id == savedID }) {
            return saved
        }
        if let matched = devices.first(where: { matchesPreferredName($0.name) }) {
            return matched
        }
        return devices.first(where: { $0.device.deviceType == .external }) ?? devices.first
    }

    /// Полный список audio-устройств для UI/выбора. Пытается найти всё, что может быть
    /// аудиовходом: внешние UVC-микрофоны (HDMI карты), встроенные микрофоны, USB audio.
    static func audioDevices() -> [CaptureDeviceInfo] {
        var seen = Set<String>()
        var result: [CaptureDeviceInfo] = []

        var deviceTypes: [AVCaptureDevice.DeviceType] = [.external]
        if #available(macOS 14.0, *) {
            deviceTypes.append(.microphone)
        } else {
            deviceTypes.append(.builtInMicrophone)
        }

        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .audio,
            position: .unspecified
        )

        for device in session.devices where !seen.contains(device.uniqueID) {
            seen.insert(device.uniqueID)
            result.append(CaptureDeviceInfo(id: device.uniqueID, name: device.localizedName, device: device))
        }

        // Fallback: если ничего не нашли через DiscoverySession (некоторые UVC-карты на
        // macOS 14+ числятся не как .microphone и не как .external), берём legacy API.
        if result.isEmpty {
            let legacy = AVCaptureDevice.devices(for: .audio)
            for device in legacy where !seen.contains(device.uniqueID) {
                seen.insert(device.uniqueID)
                result.append(CaptureDeviceInfo(id: device.uniqueID, name: device.localizedName, device: device))
            }
        }

        return result
    }

    static func audioDevice(matchingVideoName videoName: String, savedID: String? = nil) -> AVCaptureDevice? {
        let devices = audioDevices()

        if let savedID, let saved = devices.first(where: { $0.id == savedID }) {
            return saved.device
        }

        let videoTokens = tokenize(videoName)
        if let matched = devices.first(where: { info in
            !Set(videoTokens).isDisjoint(with: tokenize(info.name))
        }) {
            return matched.device
        }

        if let preferred = devices.first(where: { matchesPreferredName($0.name) }) {
            return preferred.device
        }

        // Последний шанс: первое external. .builtInMicrophone берём только если ничего нет.
        if let external = devices.first(where: { $0.device.deviceType == .external }) {
            return external.device
        }
        return devices.first?.device
    }

    private static func matchesPreferredName(_ name: String) -> Bool {
        let lower = name.lowercased()
        return preferredNameTokens.contains { lower.contains($0) }
    }

    private static func tokenize(_ name: String) -> [String] {
        name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
