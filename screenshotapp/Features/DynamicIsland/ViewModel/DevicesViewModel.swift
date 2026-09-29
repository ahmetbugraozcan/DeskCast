import AppKit
import Combine

/// Battery levels of connected accessories for the island's Devices panel.
/// Polls only while the panel is on screen.
@MainActor
final class DevicesViewModel: ObservableObject, IslandPanelActivating {
    @Published private(set) var devices: [DeviceBattery] = []
    @Published private(set) var hasLoaded = false

    let ble: BLEBatteryService
    private let listing: BluetoothDeviceListing
    private var profilerDevices: [DeviceBattery] = []
    private var timer: Timer?
    private var bleObserver: AnyCancellable?

    private static let pollInterval: TimeInterval = 30

    init(listing: BluetoothDeviceListing = SystemProfilerBluetoothService(), ble: BLEBatteryService? = nil) {
        self.listing = listing
        self.ble = ble ?? BLEBatteryService()
        bleObserver = self.ble.$levels
            .sink { [weak self] levels in
                guard let self else { return }
                devices = Self.merge(profilerDevices, bleLevels: levels)
            }
    }

    func setActive(_ active: Bool) {
        timer?.invalidate()
        timer = nil
        guard active else { return }

        reload()
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func requestBluetoothAccess() {
        ble.requestAccess()
    }

    func openBluetoothPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") {
            NSWorkspace.shared.open(url)
        }
    }

    private func reload() {
        ble.refresh()
        Task { [weak self, listing] in
            let found = await listing.connectedDevices()
            guard let self else { return }
            profilerDevices = found
            devices = Self.merge(found, bleLevels: ble.levels)
            hasLoaded = true
        }
    }

    /// Fills in levels that only Bluetooth LE reports, adds LE devices the
    /// profiler didn't list, and puts devices with a level first.
    static func merge(_ profiler: [DeviceBattery], bleLevels: [String: Int]) -> [DeviceBattery] {
        var merged = profiler.map { device -> DeviceBattery in
            guard !device.hasBattery, let level = bleLevels[device.name] else { return device }
            var device = device
            device.main = level
            return device
        }
        let known = Set(merged.map(\.name))
        for (name, level) in bleLevels where !known.contains(name) {
            merged.append(DeviceBattery(name: name, kind: .init(minorType: nil, name: name), main: level))
        }
        return merged.sorted { lhs, rhs in
            if lhs.hasBattery != rhs.hasBattery { return lhs.hasBattery }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
