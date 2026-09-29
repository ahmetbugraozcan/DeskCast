import Foundation
import Testing
@testable import screenshotapp

struct DeviceBatteryTests {
    private let sample = """
    {"SPBluetoothDataType":[{"controller_properties":{},
      "device_connected":[
        {"Ahmet's AirPods Pro":{"device_batteryLevelLeft":"%52","device_batteryLevelRight":"51%",
                                "device_batteryLevelCase":"%80","device_minorType":"Headphones"}},
        {"MX Master 3S":{"device_minorType":"Mouse"}},
        {"Magic Keyboard":{"device_batteryLevelMain":"100%","device_minorType":"Keyboard"}}
      ],
      "device_not_connected":[
        {"Old AirPods":{"device_batteryLevelLeft":"%10","device_minorType":"Headphones"}}
      ]}]}
    """

    @Test func parsesConnectedDevicesOnly() throws {
        let devices = BluetoothBatteryParser.parse(Data(sample.utf8))
        #expect(Set(devices.map(\.name)) == ["Ahmet's AirPods Pro", "MX Master 3S", "Magic Keyboard"])

        let airPods = try #require(devices.first { $0.name == "Ahmet's AirPods Pro" })
        #expect(airPods.left == 52 && airPods.right == 51 && airPods.caseLevel == 80 && airPods.main == nil)
        #expect(airPods.kind == .headphones)
        #expect(airPods.lowestLevel == 51)

        let mouse = try #require(devices.first { $0.name == "MX Master 3S" })
        #expect(!mouse.hasBattery && mouse.kind == .mouse)
    }

    @Test func percentAcceptsLocalizedFormsAndRejectsNonsense() {
        #expect(BluetoothBatteryParser.percent("%52") == 52)
        #expect(BluetoothBatteryParser.percent("52 %") == 52)
        #expect(BluetoothBatteryParser.percent("250%") == nil)
        #expect(BluetoothBatteryParser.percent(nil) == nil)
    }

    @Test func kindFallsBackToTheName() {
        #expect(DeviceBattery.Kind(minorType: nil, name: "BT5.0 KB") == .keyboard)
        #expect(DeviceBattery.Kind(minorType: nil, name: "MX Anywhere 3") == .mouse)
        #expect(DeviceBattery.Kind(minorType: "Gamepad", name: "Controller") == .gameController)
        #expect(DeviceBattery.Kind(minorType: nil, name: "Car") == .other)
    }

    @Test @MainActor func mergeFillsLevelsFromBluetoothLE() {
        let profiler = BluetoothBatteryParser.parse(Data(sample.utf8))
        let merged = DevicesViewModel.merge(profiler, bleLevels: ["MX Master 3S": 64, "K380": 30])

        let byName = Dictionary(uniqueKeysWithValues: merged.map { ($0.name, $0) })
        #expect(byName["MX Master 3S"]?.main == 64)
        #expect(byName["K380"]?.kind == .other)
        #expect(merged.filter { !$0.hasBattery }.isEmpty)
        // AirPods keep their own left/right levels instead of an LE value.
        let withAirPodsLevel = DevicesViewModel.merge(profiler, bleLevels: ["Ahmet's AirPods Pro": 5])
        let airPods = withAirPodsLevel.filter { $0.name == "Ahmet's AirPods Pro" }
        #expect(airPods.map(\.main) == [nil])
    }

    @Test @MainActor func devicesWithoutLevelsSortLast() {
        let devices = DevicesViewModel.merge(BluetoothBatteryParser.parse(Data(sample.utf8)), bleLevels: [:])
        #expect(devices.last?.name == "MX Master 3S")
    }
}
