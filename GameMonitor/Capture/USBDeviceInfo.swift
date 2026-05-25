import Foundation
import IOKit
import IOKit.usb

enum USBSpeed: Int {
    case unknown = -1
    case low = 0      // 1.5 Mbps
    case full = 1     // 12 Mbps (USB 1.x)
    case high = 2     // 480 Mbps (USB 2.0)
    case `super` = 3  // 5 Gbps (USB 3.0)
    case superPlus = 4 // 10 Gbps (USB 3.1)
    case superPlusBy2 = 5 // 20 Gbps (USB 3.2)

    var label: String {
        switch self {
        case .unknown: return "неизвестно"
        case .low: return "USB Low (1.5 Mbps)"
        case .full: return "USB 1.x (12 Mbps)"
        case .high: return "USB 2.0 (480 Mbps)"
        case .super: return "USB 3.0 (5 Gbps)"
        case .superPlus: return "USB 3.1 (10 Gbps)"
        case .superPlusBy2: return "USB 3.2 (20 Gbps)"
        }
    }

    /// Хватит ли полосы для NV12 1080p60 (~1.5 Gbps).
    var supports1080p60RawYUV: Bool {
        switch self {
        case .super, .superPlus, .superPlusBy2: return true
        default: return false
        }
    }

    var isUSB3: Bool {
        switch self {
        case .super, .superPlus, .superPlusBy2: return true
        default: return false
        }
    }
}

struct USBDeviceInfo: Equatable {
    let vendorID: UInt16
    let productID: UInt16
    let vendorName: String
    let productName: String
    let serialNumber: String?
    let speed: USBSpeed
    let bcdUSB: UInt16

    /// Краткое описание для UI: "Elgato Cam Link 4K · USB 3.0 (5 Gbps)".
    var summary: String {
        let nameParts = [vendorName, productName]
            .filter { !$0.isEmpty }
        let name = nameParts.isEmpty ? String(format: "VID 0x%04X PID 0x%04X", vendorID, productID) : nameParts.joined(separator: " ")
        return "\(name) · \(speed.label)"
    }

    var versionString: String {
        let major = (bcdUSB >> 8) & 0xff
        let minor = (bcdUSB >> 4) & 0x0f
        let sub = bcdUSB & 0x0f
        if sub == 0 {
            return String(format: "USB %d.%d", major, minor)
        }
        return String(format: "USB %d.%d.%d", major, minor, sub)
    }

    var bandwidthWarning: String? {
        if !speed.supports1080p60RawYUV {
            return "USB-полосы недостаточно для 1080p60 NV12. Переподключите карту в порт USB 3.x."
        }
        return nil
    }
}

enum USBDeviceLookup {
    /// Ищет USB-устройство, чьё имя продукта содержит токены из имени AVCaptureDevice.
    /// Cam Link 4K в IORegistry называется "Cam Link 4K"; AVCaptureDevice.localizedName тоже.
    static func info(matchingDeviceName name: String) -> USBDeviceInfo? {
        let tokens = tokenize(name)
        guard !tokens.isEmpty else { return nil }

        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching(kIOUSBDeviceClassName)
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard kr == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var bestMatch: USBDeviceInfo?
        var bestScore = 0

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let info = readDevice(service: service) else { continue }
            let score = matchScore(deviceTokens: tokens, info: info)
            if score > bestScore {
                bestScore = score
                bestMatch = info
            }
        }

        return bestScore > 0 ? bestMatch : nil
    }

    private static func readDevice(service: io_service_t) -> USBDeviceInfo? {
        let vendorID = readU16(service: service, key: "idVendor") ?? 0
        let productID = readU16(service: service, key: "idProduct") ?? 0
        guard vendorID != 0, productID != 0 else { return nil }

        let vendorName = readString(service: service, key: "USB Vendor Name")
            ?? readString(service: service, key: "kUSBVendorString")
            ?? ""
        let productName = readString(service: service, key: "USB Product Name")
            ?? readString(service: service, key: "kUSBProductString")
            ?? ""
        let serial = readString(service: service, key: "USB Serial Number")
            ?? readString(service: service, key: "kUSBSerialNumberString")

        let speedRaw = readU8(service: service, key: "Device Speed")
            ?? readU8(service: service, key: "USB Address")
        let speed = USBSpeed(rawValue: Int(speedRaw ?? 255)) ?? .unknown

        let bcd = readU16(service: service, key: "bcdUSB")
            ?? readU16(service: service, key: "Device USB Version")
            ?? 0

        return USBDeviceInfo(
            vendorID: vendorID,
            productID: productID,
            vendorName: vendorName,
            productName: productName,
            serialNumber: serial,
            speed: speed,
            bcdUSB: bcd
        )
    }

    private static func matchScore(deviceTokens: [String], info: USBDeviceInfo) -> Int {
        let candidate = "\(info.vendorName) \(info.productName)"
        let candidateTokens = Set(tokenize(candidate))
        let intersection = candidateTokens.intersection(deviceTokens)
        return intersection.count
    }

    private static func tokenize(_ name: String) -> [String] {
        name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 }
    }

    private static func readString(service: io_service_t, key: String) -> String? {
        guard let cf = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)
        else { return nil }
        let value = cf.takeRetainedValue()
        return value as? String
    }

    private static func readU16(service: io_service_t, key: String) -> UInt16? {
        guard let cf = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)
        else { return nil }
        let value = cf.takeRetainedValue()
        if let number = value as? NSNumber {
            return number.uint16Value
        }
        return nil
    }

    private static func readU8(service: io_service_t, key: String) -> UInt8? {
        guard let cf = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)
        else { return nil }
        let value = cf.takeRetainedValue()
        if let number = value as? NSNumber {
            return number.uint8Value
        }
        return nil
    }
}
