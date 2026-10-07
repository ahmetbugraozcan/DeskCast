import AppKit
import Combine

/// The island's Computers panel: wakes computers with Wake-on-LAN and checks
/// whether they're online. Checks only while the panel is on screen.
@MainActor
final class WakeComputersViewModel: ObservableObject, IslandPanelActivating {
    @Published private(set) var computers: [WakeComputer] = []
    @Published private(set) var statuses: [UUID: WakeComputerStatus] = [:]
    /// The computer whose magic packet couldn't be sent.
    @Published private(set) var failedWake: UUID?

    private let sender: WakeOnLANSending
    private let prober: HostProbing
    private let defaults: UserDefaults
    private var timer: Timer?
    private var defaultsObserver: AnyCancellable?
    private var isChecking = false
    /// The last address each `.local` computer resolved to while online, so
    /// it can be shown as away when this Mac is on another network.
    private var lastAddresses: [String: String]

    static let lastAddressesKey = "dynamicIsland.wakeComputerAddresses"

    private static let pollInterval: TimeInterval = 4

    init(
        sender: WakeOnLANSending = WakeOnLANService(),
        prober: HostProbing = HostProbeService(),
        defaults: UserDefaults = .standard
    ) {
        self.sender = sender
        self.prober = prober
        self.defaults = defaults
        computers = WakeComputer.load(from: defaults)
        lastAddresses = defaults.dictionary(forKey: Self.lastAddressesKey) as? [String: String] ?? [:]
        defaultsObserver = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification, object: defaults)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reloadComputers() }
    }

    func status(of computer: WakeComputer) -> WakeComputerStatus {
        statuses[computer.id] ?? .unknown
    }

    func setActive(_ active: Bool) {
        timer?.invalidate()
        timer = nil
        guard active else { return }

        checkAll()
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkAll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func wake(_ computer: WakeComputer) {
        guard status(of: computer) != .away, let mac = computer.macBytes else { return }
        failedWake = nil
        Task {
            let sent = await sender.wake(mac: mac)
            if sent {
                statuses[computer.id] = .waking(since: Date())
            } else {
                failedWake = computer.id
            }
        }
    }

    func openLocalNetworkSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork") {
            NSWorkspace.shared.open(url)
        }
    }

    private func reloadComputers() {
        let loaded = WakeComputer.load(from: defaults)
        guard loaded != computers else { return }
        computers = loaded
        let ids = Set(loaded.map(\.id))
        statuses = statuses.filter { ids.contains($0.key) }
        let idStrings = Set(ids.map(\.uuidString))
        if lastAddresses.keys.contains(where: { !idStrings.contains($0) }) {
            lastAddresses = lastAddresses.filter { idStrings.contains($0.key) }
            defaults.set(lastAddresses, forKey: Self.lastAddressesKey)
        }
    }

    private func checkAll() {
        guard !isChecking else { return }
        let targets = computers.filter { !$0.trimmedHost.isEmpty }
        guard !targets.isEmpty else { return }
        isChecking = true

        Task { [prober] in
            let results = await withTaskGroup(of: (UUID, Bool).self) { group in
                for computer in targets {
                    let host = computer.trimmedHost
                    group.addTask { (computer.id, await prober.isOnline(host: host)) }
                }
                var results: [UUID: Bool] = [:]
                for await (id, online) in group {
                    results[id] = online
                }
                return results
            }
            isChecking = false
            let subnets = prober.localSubnets()
            for computer in targets {
                guard let online = results[computer.id] else { continue }
                let away = !online && LocalNetworkReach.isAway(
                    host: computer.trimmedHost,
                    lastKnownAddress: lastAddresses[computer.id.uuidString],
                    subnets: subnets
                )
                statuses[computer.id] = away ? .away : Self.next(status: statuses[computer.id] ?? .unknown, online: online, now: Date())
                if online, LocalNetworkReach.isLocalName(computer.trimmedHost) {
                    rememberAddress(of: computer)
                }
            }
        }
    }

    private func rememberAddress(of computer: WakeComputer) {
        Task { [prober] in
            guard let address = await prober.resolveIPv4(host: computer.trimmedHost),
                  lastAddresses[computer.id.uuidString] != address else { return }
            lastAddresses[computer.id.uuidString] = address
            defaults.set(lastAddresses, forKey: Self.lastAddressesKey)
        }
    }

    /// Online wins; a computer that was just woken stays "waking" until it
    /// answers or `WakeOnLAN.wakeTimeout` passes.
    nonisolated static func next(status: WakeComputerStatus, online: Bool, now: Date) -> WakeComputerStatus {
        if online { return .online }
        if case .waking(let since) = status, now.timeIntervalSince(since) < WakeOnLAN.wakeTimeout {
            return status
        }
        return .offline
    }
}
