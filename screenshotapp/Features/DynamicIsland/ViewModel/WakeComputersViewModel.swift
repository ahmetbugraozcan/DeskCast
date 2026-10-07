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
        guard let mac = computer.macBytes else { return }
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
            for (id, online) in results {
                statuses[id] = Self.next(status: statuses[id] ?? .unknown, online: online, now: Date())
            }
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
