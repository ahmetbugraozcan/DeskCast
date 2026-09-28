import AppKit
import Combine

/// Presentation boundary for the island panel; the view model publishes state
/// and drives the AppKit panel through this protocol.
@MainActor
protocol DynamicIslandPresenting: AnyObject {
    var isVisible: Bool { get }
    func refresh()
    func hide()
}

/// Lets other features (e.g. the toast presenter) hand transient messages to the
/// island instead of showing their own panel.
@MainActor
protocol DynamicIslandNotificationPosting: AnyObject {
    /// Returns `true` when the island took the message, so the caller skips its own UI.
    func postToast(_ message: String, systemImage: String, style: ToastStyle) -> Bool
}

@MainActor
final class DynamicIslandViewModel: ObservableObject, DynamicIslandNotificationPosting {
    @Published private(set) var nowPlaying: NowPlayingInfo?
    @Published private(set) var activeNotification: DynamicIslandNotification?
    @Published private(set) var isHovering = false
    @Published private(set) var isPinnedOpen = false
    @Published private(set) var geometry = DynamicIslandGeometry.fallback
    @Published private(set) var isEnabled = false
    @Published private(set) var preferences: DynamicIslandSettingsSnapshot

    weak var presenter: DynamicIslandPresenting?

    private let nowPlayingService: NowPlayingProviding
    private let batteryMonitor: BatteryMonitoring
    private let settings: DynamicIslandSettingsReading & ToolboxSettingsReading
    private var pendingNotifications: [DynamicIslandNotification] = []
    private var notificationDismissTask: Task<Void, Never>?
    private var hoverEndTask: Task<Void, Never>?
    private var lastBatteryStatus: BatteryStatus?
    private var hasReceivedNowPlaying = false
    private var defaultsObserver: AnyCancellable?

    private static let maxQueuedNotifications = 4
    private static let hoverEndDelay: Duration = .milliseconds(160)
    private static let lowBatteryThresholds = [20, 10]

    init(
        nowPlayingService: NowPlayingProviding,
        batteryMonitor: BatteryMonitoring,
        settings: DynamicIslandSettingsReading & ToolboxSettingsReading
    ) {
        self.nowPlayingService = nowPlayingService
        self.batteryMonitor = batteryMonitor
        self.settings = settings
        preferences = settings.dynamicIslandSettings()

        nowPlayingService.onChange = { [weak self] info in
            self?.handleNowPlayingChange(info)
        }
        batteryMonitor.onChange = { [weak self] status in
            self?.handleBatteryChange(status)
        }

        defaultsObserver = NotificationCenter.default.publisher(
            for: UserDefaults.didChangeNotification,
            object: UserDefaults.standard
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            Task { @MainActor in
                self?.applySettingsChange()
            }
        }
    }

    /// Called once the presenter is wired so the first refresh can show the panel.
    func start() {
        applySettingsChange(force: true)
    }

    // MARK: - Derived state

    var mode: DynamicIslandMode {
        if (isHovering && preferences.expandsOnHover) || isPinnedOpen {
            return .expanded
        }

        if activeNotification != nil {
            return .notification
        }

        if hasMedia {
            return .compactMedia
        }

        return .idle
    }

    var hasMedia: Bool {
        preferences.showsNowPlaying && nowPlaying != nil
    }

    // MARK: - Interaction (driven by the panel coordinator / view)

    func updateGeometry(_ geometry: DynamicIslandGeometry) {
        guard self.geometry != geometry else { return }
        self.geometry = geometry
    }

    func setHovering(_ hovering: Bool) {
        if hovering {
            hoverEndTask?.cancel()
            hoverEndTask = nil

            if !isHovering {
                isHovering = true
            }

            return
        }

        guard isHovering || isPinnedOpen, hoverEndTask == nil else { return }

        // A short grace period keeps the island from snapping shut when the
        // pointer brushes the edge while moving between controls.
        hoverEndTask = Task { [weak self] in
            try? await Task.sleep(for: Self.hoverEndDelay)
            guard !Task.isCancelled, let self else { return }
            self.hoverEndTask = nil
            self.isHovering = false
            self.isPinnedOpen = false
        }
    }

    /// Click-to-expand, used when hover expansion is turned off.
    func toggleExpanded() {
        guard !(isHovering && preferences.expandsOnHover) else { return }
        isPinnedOpen.toggle()
    }

    func togglePlayPause() {
        guard let nowPlaying else { return }
        nowPlayingService.send(.togglePlayPause, to: nowPlaying.player)
        // Optimistic flip; the next player notification confirms it.
        self.nowPlaying = nowPlaying.togglingPlayback()
    }

    func nextTrack() {
        guard let nowPlaying else { return }
        nowPlayingService.send(.nextTrack, to: nowPlaying.player)
    }

    func previousTrack() {
        guard let nowPlaying else { return }
        nowPlayingService.send(.previousTrack, to: nowPlaying.player)
    }

    func openPlayer(_ player: MediaPlayerApp? = nil) {
        guard
            let player = player ?? nowPlaying?.player,
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.bundleIdentifier)
        else {
            return
        }

        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func dismissNotification() {
        notificationDismissTask?.cancel()
        notificationDismissTask = nil

        if pendingNotifications.isEmpty {
            activeNotification = nil
        } else {
            show(pendingNotifications.removeFirst())
        }
    }

    // MARK: - Notifications

    func post(_ notification: DynamicIslandNotification) {
        guard isEnabled else { return }

        guard activeNotification != nil else {
            show(notification)
            return
        }

        // A newer track replaces an on-screen track banner instead of queueing.
        if notification.style == .media, activeNotification?.style == .media {
            show(notification)
            return
        }

        pendingNotifications.removeAll { $0.style == .media && notification.style == .media }
        pendingNotifications.append(notification)

        if pendingNotifications.count > Self.maxQueuedNotifications {
            pendingNotifications.removeFirst(pendingNotifications.count - Self.maxQueuedNotifications)
        }
    }

    func postToast(_ message: String, systemImage: String, style: ToastStyle) -> Bool {
        guard isEnabled, preferences.showsAppNotifications, presenter?.isVisible == true else {
            return false
        }

        post(
            DynamicIslandNotification(
                title: AppConstants.displayName,
                message: message,
                systemImage: systemImage,
                style: DynamicIslandNotificationStyle(style)
            )
        )
        return true
    }

    private func show(_ notification: DynamicIslandNotification) {
        notificationDismissTask?.cancel()
        activeNotification = notification

        let duration = Duration.seconds(preferences.notificationDurationSeconds)
        let id = notification.id

        notificationDismissTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self, self.activeNotification?.id == id else { return }
            self.dismissNotification()
        }
    }

    private func clearNotifications() {
        notificationDismissTask?.cancel()
        notificationDismissTask = nil
        pendingNotifications = []
        activeNotification = nil
    }

    // MARK: - Sources

    private func handleNowPlayingChange(_ info: NowPlayingInfo?) {
        let previous = nowPlaying
        nowPlaying = info

        defer { hasReceivedNowPlaying = true }

        guard let info else { return }

        // Artwork often arrives after the track; patch an on-screen banner for it.
        if info.isSameTrack(as: previous) {
            if let artwork = info.artwork,
               var banner = activeNotification,
               banner.style == .media,
               banner.mediaKey == info.cacheKey,
               banner.image == nil {
                banner.image = artwork
                activeNotification = banner
            }

            return
        }

        guard
            hasReceivedNowPlaying,
            info.isPlaying,
            preferences.showsTrackChanges,
            !isHovering
        else {
            return
        }

        var banner = DynamicIslandNotification(
            title: info.title.isEmpty ? info.player.displayName : info.title,
            message: info.artist.isEmpty ? info.album : info.artist,
            systemImage: "music.note",
            style: .media,
            image: info.artwork
        )
        banner.mediaKey = info.cacheKey
        post(banner)
    }

    private func handleBatteryChange(_ status: BatteryStatus) {
        let previous = lastBatteryStatus
        lastBatteryStatus = status

        guard let previous, preferences.showsBatteryEvents else { return }

        let progress = Double(status.level) / 100

        if status.isPluggedIn != previous.isPluggedIn {
            post(
                DynamicIslandNotification(
                    title: AppLocalization.string(status.isPluggedIn ? "Charging" : "On Battery"),
                    message: AppLocalization.formatted("Battery at %ld%%", status.level),
                    systemImage: status.isPluggedIn ? "battery.100percent.bolt" : "battery.75percent",
                    style: .battery,
                    progress: progress
                )
            )
            return
        }

        guard !status.isPluggedIn else { return }

        let crossedThreshold = Self.lowBatteryThresholds.contains { threshold in
            previous.level > threshold && status.level <= threshold
        }

        if crossedThreshold {
            post(
                DynamicIslandNotification(
                    title: AppLocalization.string("Low Battery"),
                    message: AppLocalization.formatted("Battery at %ld%%", status.level),
                    systemImage: "battery.25percent",
                    style: .warning,
                    progress: progress
                )
            )
        }
    }

    // MARK: - Settings

    private func applySettingsChange(force: Bool = false) {
        let newPreferences = settings.dynamicIslandSettings()
        let newIsEnabled = settings.isToolEnabled(.dynamicIsland)

        guard force || newPreferences != preferences || newIsEnabled != isEnabled else { return }

        preferences = newPreferences
        isEnabled = newIsEnabled

        if isEnabled && preferences.showsNowPlaying {
            nowPlayingService.start()
        } else {
            nowPlayingService.stop()
            nowPlaying = nil
            hasReceivedNowPlaying = false
        }

        if isEnabled && preferences.showsBatteryEvents {
            batteryMonitor.start()
            lastBatteryStatus = lastBatteryStatus ?? batteryMonitor.currentStatus()
        } else {
            batteryMonitor.stop()
            lastBatteryStatus = nil
        }

        if !isEnabled {
            clearNotifications()
            hoverEndTask?.cancel()
            hoverEndTask = nil
            isHovering = false
            isPinnedOpen = false
            presenter?.hide()
        } else {
            presenter?.refresh()
        }
    }
}

private extension DynamicIslandNotificationStyle {
    init(_ toastStyle: ToastStyle) {
        switch toastStyle {
        case .success: self = .success
        case .warning: self = .warning
        case .error: self = .error
        }
    }
}
