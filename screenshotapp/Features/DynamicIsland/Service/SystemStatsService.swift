import Darwin
import Foundation
import IOKit
import IOKit.ps

nonisolated struct SystemStatsSnapshot: Equatable, Sendable {
    /// 0...1 fractions.
    var cpuUsage: Double = 0
    var gpuUsage: Double?
    var memoryUsage: Double = 0
    var memoryUsedBytes: UInt64 = 0
    var memoryTotalBytes: UInt64 = 0
    var batteryLevel: Int?
    var isCharging = false
    var isPluggedIn = false
    /// Bytes per second over the last sample interval.
    var downloadBytesPerSecond: Double = 0
    var uploadBytesPerSecond: Double = 0
    var diskAvailableBytes: Int64 = 0
    var diskTotalBytes: Int64 = 0
    /// Current system power draw and connected adapter rating, in watts.
    var systemPowerWatts: Double?
    var adapterWatts: Int?

    var diskAvailableFraction: Double {
        diskTotalBytes > 0 ? Double(diskAvailableBytes) / Double(diskTotalBytes) : 0
    }
}

/// Reads CPU/memory through Mach host statistics, GPU through IOAccelerator
/// performance statistics, network through interface byte counters, and
/// battery/power through IOKit power sources and AppleSmartBattery. None of it
/// needs a permission. Not thread-safe: call `sample()` from one serial queue.
nonisolated final class SystemStatsService: @unchecked Sendable {
    private var previousCPUTicks: (busy: UInt64, total: UInt64)?
    private var previousNetwork: (received: UInt64, sent: UInt64, date: Date)?

    /// Takes one sample. Rates (CPU, network) are measured against the
    /// previous call, so the first sample reports zero for them.
    func sample() -> SystemStatsSnapshot {
        var snapshot = SystemStatsSnapshot()
        snapshot.cpuUsage = cpuUsage()
        snapshot.gpuUsage = gpuUsage()

        let memory = memoryUsage()
        snapshot.memoryUsedBytes = memory.used
        snapshot.memoryTotalBytes = memory.total
        snapshot.memoryUsage = memory.total > 0 ? Double(memory.used) / Double(memory.total) : 0

        let network = networkRates()
        snapshot.downloadBytesPerSecond = network.down
        snapshot.uploadBytesPerSecond = network.up

        if let disk = diskCapacity() {
            snapshot.diskAvailableBytes = disk.available
            snapshot.diskTotalBytes = disk.total
        }

        let battery = batteryState()
        snapshot.batteryLevel = battery?.level
        snapshot.isCharging = battery?.isCharging ?? false
        snapshot.isPluggedIn = battery?.isPluggedIn ?? true
        snapshot.systemPowerWatts = systemPowerWatts()
        snapshot.adapterWatts = adapterWatts()

        return snapshot
    }

    // MARK: - CPU

    private func cpuUsage() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )

        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, reboundPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else { return 0 }

        let user = UInt64(info.cpu_ticks.0)
        let system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2)
        let nice = UInt64(info.cpu_ticks.3)
        let busy = user + system + nice
        let total = busy + idle

        defer { previousCPUTicks = (busy, total) }

        guard let previous = previousCPUTicks, total > previous.total else { return 0 }

        let busyDelta = Double(busy &- previous.busy)
        let totalDelta = Double(total &- previous.total)
        return min(max(busyDelta / totalDelta, 0), 1)
    }

    // MARK: - Memory

    /// "Used" as Activity Monitor reports it: app memory + wired + compressed.
    private func memoryUsage() -> (used: UInt64, total: UInt64) {
        let total = ProcessInfo.processInfo.physicalMemory
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )

        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else { return (0, total) }

        let pageSize = UInt64(vm_kernel_page_size)
        let appPages = UInt64(stats.internal_page_count) - min(UInt64(stats.purgeable_count), UInt64(stats.internal_page_count))
        let usedPages = appPages + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        return (min(usedPages * pageSize, total), total)
    }

    // MARK: - GPU

    private func gpuUsage() -> Double? {
        var iterator: io_iterator_t = 0

        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            return nil
        }

        defer { IOObjectRelease(iterator) }

        var highest: Double?
        var service = IOIteratorNext(iterator)

        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            var properties: Unmanaged<CFMutableDictionary>?

            guard
                IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                let dictionary = properties?.takeRetainedValue() as? [String: Any],
                let statistics = dictionary["PerformanceStatistics"] as? [String: Any],
                let utilization = (statistics["Device Utilization %"] ?? statistics["GPU Activity(%)"]) as? NSNumber
            else {
                continue
            }

            highest = max(highest ?? 0, utilization.doubleValue / 100)
        }

        return highest.map { min(max($0, 0), 1) }
    }

    // MARK: - Network

    private func networkRates() -> (down: Double, up: Double) {
        var interfaces: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return (0, 0) }

        defer { freeifaddrs(interfaces) }

        var received: UInt64 = 0
        var sent: UInt64 = 0
        var pointer: UnsafeMutablePointer<ifaddrs>? = first

        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }

            let interface = current.pointee
            let name = String(cString: interface.ifa_name)

            // Physical Wi-Fi/Ethernet only; VPN tunnels would double count.
            guard
                name.hasPrefix("en"),
                let address = interface.ifa_addr,
                address.pointee.sa_family == UInt8(AF_LINK),
                let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self)
            else {
                continue
            }

            received += UInt64(data.pointee.ifi_ibytes)
            sent += UInt64(data.pointee.ifi_obytes)
        }

        let now = Date()
        defer { previousNetwork = (received, sent, now) }

        guard let previous = previousNetwork else { return (0, 0) }

        let interval = now.timeIntervalSince(previous.date)
        guard interval > 0 else { return (0, 0) }

        // Counters are 32-bit per interface and wrap; a negative delta is a wrap
        // or an interface going away, so skip that sample instead of spiking.
        let down = received >= previous.received ? Double(received - previous.received) / interval : 0
        let up = sent >= previous.sent ? Double(sent - previous.sent) / interval : 0
        return (down, up)
    }

    // MARK: - Disk

    private func diskCapacity() -> (available: Int64, total: Int64)? {
        let url = URL(fileURLWithPath: "/")
        let values = try? url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey
        ])

        guard let available = values?.volumeAvailableCapacityForImportantUsage,
              let total = values?.volumeTotalCapacity
        else {
            return nil
        }

        return (available, Int64(total))
    }

    // MARK: - Battery & power

    private func batteryState() -> (level: Int, isCharging: Bool, isPluggedIn: Bool)? {
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

            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = description[kIOPSMaxCapacityKey] as? Int ?? 100
            let level = maximum > 0 ? Int((Double(current) / Double(maximum) * 100).rounded()) : current

            return (
                min(max(level, 0), 100),
                description[kIOPSIsChargingKey] as? Bool ?? false,
                description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            )
        }

        return nil
    }

    private func adapterWatts() -> Int? {
        guard let details = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] else {
            return nil
        }

        return (details[kIOPSPowerAdapterWattsKey] as? NSNumber)?.intValue
    }

    /// Whole-system draw. Prefers the SMC telemetry (valid on AC and battery),
    /// falling back to battery voltage × current.
    private func systemPowerWatts() -> Double? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))

        guard service != 0 else { return nil }

        defer { IOObjectRelease(service) }

        var properties: Unmanaged<CFMutableDictionary>?

        guard
            IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
            let dictionary = properties?.takeRetainedValue() as? [String: Any]
        else {
            return nil
        }

        if let telemetry = dictionary["PowerTelemetryData"] as? [String: Any],
           let systemPowerIn = (telemetry["SystemPowerIn"] as? NSNumber)?.doubleValue,
           systemPowerIn > 0 {
            return systemPowerIn / 1000
        }

        guard
            let voltage = (dictionary["Voltage"] as? NSNumber)?.doubleValue,
            let amperage = (dictionary["InstantAmperage"] ?? dictionary["Amperage"]) as? NSNumber
        else {
            return nil
        }

        // Amperage is a signed 64-bit value stored unsigned in the registry.
        let milliamps = Double(Int64(bitPattern: amperage.uint64Value))
        let watts = abs(voltage * milliamps) / 1_000_000
        return watts > 0 ? watts : nil
    }
}
