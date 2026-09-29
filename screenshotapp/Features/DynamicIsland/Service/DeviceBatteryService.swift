import Combine
import CoreBluetooth
import Foundation

/// Connected Bluetooth devices from `system_profiler` (AirPods left/right/case,
/// Apple keyboards, mice and trackpads, many headphones). No permission needed.
nonisolated protocol BluetoothDeviceListing: Sendable {
    func connectedDevices() async -> [DeviceBattery]
}

nonisolated struct SystemProfilerBluetoothService: BluetoothDeviceListing {
    func connectedDevices() async -> [DeviceBattery] {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["SPBluetoothDataType", "-json", "-timeout", "5"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                return []
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return BluetoothBatteryParser.parse(data)
        }.value
    }
}

/// Battery levels from Bluetooth LE devices that publish the standard Battery
/// Service (0x180F) — e.g. Logitech MX mice and many keyboards, which
/// `system_profiler` lists without a level. Needs Bluetooth permission, so the
/// central manager is only created once the user asks for it.
@MainActor
final class BLEBatteryService: NSObject, ObservableObject {
    enum Access: Equatable {
        case notRequested, allowed, denied, unavailable
    }

    @Published private(set) var access: Access
    /// Latest level per peripheral name.
    @Published private(set) var levels: [String: Int] = [:]

    private var central: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private static let batteryService = CBUUID(string: "180F")
    private static let batteryLevel = CBUUID(string: "2A19")

    override init() {
        switch CBManager.authorization {
        case .allowedAlways: access = .allowed
        case .denied, .restricted: access = .denied
        default: access = .notRequested
        }
        super.init()
    }

    /// Creates the central manager, which shows the permission prompt once.
    func requestAccess() {
        guard central == nil, access != .denied else { return }
        central = CBCentralManager(delegate: self, queue: .main)
    }

    /// Reads every connected peripheral's battery level again.
    func refresh() {
        if central == nil, access == .allowed {
            requestAccess()
            return
        }
        guard let central, central.state == .poweredOn else { return }

        for peripheral in central.retrieveConnectedPeripherals(withServices: [Self.batteryService]) {
            peripherals[peripheral.identifier] = peripheral
            peripheral.delegate = self
            if peripheral.state == .connected {
                readBattery(of: peripheral)
            } else {
                // Joins the system's existing connection; no pairing happens.
                central.connect(peripheral)
            }
        }
    }

    private func readBattery(of peripheral: CBPeripheral) {
        if let characteristic = peripheral.services?
            .first(where: { $0.uuid == Self.batteryService })?
            .characteristics?.first(where: { $0.uuid == Self.batteryLevel }) {
            peripheral.readValue(for: characteristic)
        } else {
            peripheral.discoverServices([Self.batteryService])
        }
    }

    fileprivate func store(level: Int, for peripheral: CBPeripheral) {
        guard let name = peripheral.name, (0...100).contains(level) else { return }
        levels[name] = level
    }
}

extension BLEBatteryService: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        MainActor.assumeIsolated {
            switch state {
            case .poweredOn:
                access = .allowed
                refresh()
            case .unauthorized:
                access = .denied
            case .unsupported, .poweredOff:
                access = .unavailable
            default:
                break
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated { readBattery(of: peripheral) }
    }
}

extension BLEBatteryService: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            guard let service = peripheral.services?.first(where: { $0.uuid == Self.batteryService }) else { return }
            peripheral.discoverCharacteristics([Self.batteryLevel], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        MainActor.assumeIsolated {
            guard let characteristic = service.characteristics?.first(where: { $0.uuid == Self.batteryLevel }) else { return }
            peripheral.readValue(for: characteristic)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let byte = characteristic.value?.first else { return }
        MainActor.assumeIsolated { store(level: Int(byte), for: peripheral) }
    }
}
