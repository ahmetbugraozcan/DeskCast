import Foundation

/// A connected accessory and whatever battery levels it reports (0–100).
nonisolated struct DeviceBattery: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case headphones, keyboard, mouse, trackpad, gameController, speaker, other

        init(minorType: String?, name: String) {
            let hint = "\(minorType ?? "") \(name)".lowercased()
            if hint.contains("headphone") || hint.contains("headset") || hint.contains("airpods") || hint.contains("buds") {
                self = .headphones
            } else if hint.contains("keyboard") || hint.contains(" kb") {
                self = .keyboard
            } else if hint.contains("trackpad") {
                self = .trackpad
            } else if hint.contains("mouse") || hint.contains("mx master") || hint.contains("mx anywhere") {
                self = .mouse
            } else if hint.contains("gamepad") || hint.contains("controller") || hint.contains("joystick") {
                self = .gameController
            } else if hint.contains("speaker") {
                self = .speaker
            } else {
                self = .other
            }
        }

        var titleKey: String { "island.devices.kind.\(rawValue)" }

        var systemImage: String {
            switch self {
            case .headphones: "airpods"
            case .keyboard: "keyboard"
            case .mouse: "computermouse"
            case .trackpad: "rectangle.and.hand.point.up.left"
            case .gameController: "gamecontroller"
            case .speaker: "hifispeaker"
            case .other: "dot.radiowaves.left.and.right"
            }
        }
    }

    var id: String { name }
    let name: String
    let kind: Kind
    var main: Int?
    var left: Int?
    var right: Int?
    var caseLevel: Int?

    var hasBattery: Bool {
        [main, left, right, caseLevel].contains { $0 != nil }
    }

    /// The level that decides "low": the emptiest part that reports one.
    var lowestLevel: Int? {
        [main, left, right].compactMap { $0 }.min()
    }
}

/// Reads `system_profiler SPBluetoothDataType -json`. Only connected devices
/// are returned: macOS keeps stale levels for disconnected AirPods.
nonisolated enum BluetoothBatteryParser {
    static func parse(_ data: Data) -> [DeviceBattery] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]] else { return [] }

        return controllers.flatMap { controller -> [DeviceBattery] in
            let connected = controller["device_connected"] as? [[String: [String: Any]]] ?? []
            return connected.flatMap { entry in
                entry.map { name, info in
                    DeviceBattery(
                        name: name,
                        kind: .init(minorType: info["device_minorType"] as? String, name: name),
                        main: percent(info["device_batteryLevelMain"]),
                        left: percent(info["device_batteryLevelLeft"]),
                        right: percent(info["device_batteryLevelRight"]),
                        caseLevel: percent(info["device_batteryLevelCase"])
                    )
                }
            }
        }
    }

    /// Values look like "52%" or, in a Turkish locale, "%52".
    static func percent(_ value: Any?) -> Int? {
        guard let text = value as? String else { return nil }
        let digits = text.filter(\.isNumber)
        guard let number = Int(digits), (0...100).contains(number) else { return nil }
        return number
    }
}
