import Foundation
import IOKit.ps

nonisolated struct BatteryStatus: Equatable, Sendable {
    /// Charge level in 0...100.
    let level: Int
    let isCharging: Bool
    let isPluggedIn: Bool
}

@MainActor
protocol BatteryMonitoring: AnyObject {
    var onChange: ((BatteryStatus) -> Void)? { get set }
    func start()
    func stop()
    func currentStatus() -> BatteryStatus?
}

/// Publishes internal-battery changes through IOKit power-source notifications.
/// Desktops without a battery simply never report a status.
@MainActor
final class BatteryMonitorService: BatteryMonitoring {
    var onChange: ((BatteryStatus) -> Void)?

    private var runLoopSource: CFRunLoopSource?
    private var lastStatus: BatteryStatus?

    func start() {
        guard runLoopSource == nil else { return }

        // The service lives for the app's lifetime (retained by the view model),
        // and `stop()` removes the source before it could outlive `self`.
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let service = Unmanaged<BatteryMonitorService>.fromOpaque(context).takeUnretainedValue()

            // The source is added to the main run loop, so this runs on main.
            MainActor.assumeIsolated {
                service.emitIfChanged()
            }
        }

        guard let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() else {
            return
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        runLoopSource = source
        lastStatus = currentStatus()
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        runLoopSource = nil
        lastStatus = nil
    }

    func currentStatus() -> BatteryStatus? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return nil
        }

        for source in sources {
            guard
                let description = IOPSGetPowerSourceDescription(info, source)?
                    .takeUnretainedValue() as? [String: Any],
                description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else {
                continue
            }

            let currentCapacity = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maxCapacity = description[kIOPSMaxCapacityKey] as? Int ?? 100
            let level = maxCapacity > 0
                ? Int((Double(currentCapacity) / Double(maxCapacity) * 100).rounded())
                : currentCapacity

            return BatteryStatus(
                level: min(max(level, 0), 100),
                isCharging: description[kIOPSIsChargingKey] as? Bool ?? false,
                isPluggedIn: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            )
        }

        return nil
    }

    private func emitIfChanged() {
        guard let status = currentStatus(), status != lastStatus else { return }
        lastStatus = status
        onChange?(status)
    }
}
