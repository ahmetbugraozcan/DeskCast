import AppKit
import Combine
import KeyboardShortcuts

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
    /// Sticky open from the pin button; only the pin/collapse buttons close it.
    @Published private(set) var isPinned = false
    /// Opened by a click or shortcut; closes on an outside click, or when the
    /// pointer leaves after having entered.
    @Published private(set) var isForcedOpen = false
    @Published private(set) var expandedContent: IslandExpandedContent
    @Published private(set) var notificationHistory: [DynamicIslandNotification] = []
    @Published private(set) var geometry = DynamicIslandGeometry.fallback
    @Published private(set) var isEnabled = false
    @Published private(set) var preferences: DynamicIslandSettingsSnapshot

    weak var presenter: DynamicIslandPresenting?

    private let nowPlayingService: NowPlayingProviding
    private let batteryMonitor: BatteryMonitoring
    private let systemNotifications: SystemNotificationMonitoring
    private let settings: DynamicIslandSettingsReading & ToolboxSettingsReading
    private var pendingNotifications: [DynamicIslandNotification] = []
    private var notificationDismissTask: Task<Void, Never>?
    private var hoverEndTask: Task<Void, Never>?
    private var lastBatteryStatus: BatteryStatus?
    private var hasReceivedNowPlaying = false
    private var defaultsObserver: AnyCancellable?
    private var timerObserver: AnyCancellable?
    private var pointerEnteredSinceForcedOpen = false
    /// After the collapse button, ignore hover until the pointer leaves once.
    private var suppressesHoverUntilExit = false
    private var hasRegisteredShortcuts = false

    let timer: IslandTimerViewModel

    private static let maxQueuedNotifications = 4
    private static let hoverEndDelay: Duration = .milliseconds(160)
    private static let lowBatteryThresholds = [20, 10]
    private static let maxHistoryCount = 30
    private static let lastPanelKey = "dynamicIsland.lastPanel"

    init(
        nowPlayingService: NowPlayingProviding,
        batteryMonitor: BatteryMonitoring,
        systemNotifications: SystemNotificationMonitoring,
        timer: IslandTimerViewModel? = nil,
        settings: DynamicIslandSettingsReading & ToolboxSettingsReading
    ) {
        self.timer = timer ?? IslandTimerViewModel()
        self.nowPlayingService = nowPlayingService
        self.batteryMonitor = batteryMonitor
        self.systemNotifications = systemNotifications
        self.settings = settings
        preferences = settings.dynamicIslandSettings()
        let lastPanel = UserDefaults.standard.string(forKey: Self.lastPanelKey).flatMap(IslandPanel.init(rawValue:))
        expandedContent = .panel(lastPanel ?? .nowPlaying)

        nowPlayingService.onChange = { [weak self] info in
            self?.handleNowPlayingChange(info)
        }
        batteryMonitor.onChange = { [weak self] status in
            self?.handleBatteryChange(status)
        }
        systemNotifications.onBanner = { [weak self] banner in
            self?.handleSystemBanner(banner)
        }

        // The compact island shows the running timer, so re-render with it.
        timerObserver = self.timer.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        self.timer.onFinish = { [weak self] in
            self?.post(
                DynamicIslandNotification(
                    title: AppLocalization.string("island.timer.finished"),
                    message: nil,
                    systemImage: "timer",
                    style: .warning
                )
            )
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

        #if DEBUG
        applyDemoLaunchOptions()
        #endif
    }

    // MARK: - Derived state

    var mode: DynamicIslandMode {
        if isPinned || isForcedOpen {
            return .expanded
        }

        // A banner stays put while hovered so it can be read and clicked.
        if activeNotification != nil {
            return .notification
        }

        if isExpandedByHover {
            return .expanded
        }

        if hasMedia {
            return .compactMedia
        }

        if timer.isActive {
            return .compactTimer
        }

        return .idle
    }

    private var isExpandedByHover: Bool {
        isHovering && preferences.expandsOnHover && !suppressesHoverUntilExit
    }

    var availablePlayers: [MediaPlayerApp] {
        MediaPlayerApp.allCases.filter(\.isRunning)
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

            pointerEnteredSinceForcedOpen = true

            if !isHovering {
                isHovering = true
                // Hold the banner while the pointer is on it.
                notificationDismissTask?.cancel()
                notificationDismissTask = nil
            }

            return
        }

        guard isHovering || (isForcedOpen && pointerEnteredSinceForcedOpen), hoverEndTask == nil else {
            return
        }

        // A short grace period keeps the island from snapping shut when the
        // pointer brushes the edge while moving between controls.
        hoverEndTask = Task { [weak self] in
            try? await Task.sleep(for: Self.hoverEndDelay)
            guard !Task.isCancelled, let self else { return }
            self.hoverEndTask = nil
            self.isHovering = false
            self.suppressesHoverUntilExit = false

            if self.isForcedOpen, self.pointerEnteredSinceForcedOpen {
                self.isForcedOpen = false
            }

            if let notification = self.activeNotification {
                self.scheduleDismiss(of: notification)
            }
        }
    }

    /// Clicking a banner opens the app that posted it; otherwise it toggles
    /// click-to-expand.
    func handleTap() {
        // Taps on an open island belong to its panel content, never close it.
        guard mode != .expanded else { return }

        guard mode == .notification, let notification = activeNotification else {
            toggleExpanded()
            return
        }

        if let url = notification.sourceAppURL {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } else if notification.style == .media {
            openPlayer()
        }

        dismissNotification()
    }

    /// Click-to-expand, used when hover expansion is turned off.
    func toggleExpanded() {
        guard !isExpandedByHover || isForcedOpen else { return }
        isForcedOpen.toggle()
        pointerEnteredSinceForcedOpen = isHovering
    }

    /// A click anywhere outside the island closes a click/shortcut-opened island.
    func handleOutsideClick() {
        guard isForcedOpen, !isPinned else { return }
        isForcedOpen = false
    }

    // MARK: - Panels

    func select(_ panel: IslandPanel) {
        expandedContent = .panel(panel)
        UserDefaults.standard.set(panel.rawValue, forKey: Self.lastPanelKey)
    }

    func showLauncher() {
        expandedContent = expandedContent == .launcher ? lastPanelContent : .launcher
    }

    /// Opens the island on a panel (side buttons, shortcuts); toggles closed when
    /// that panel is already showing.
    func open(_ panel: IslandPanel) {
        if mode == .expanded, expandedContent == .panel(panel) {
            collapse()
            return
        }

        select(panel)

        if mode != .expanded {
            isForcedOpen = true
            pointerEnteredSinceForcedOpen = isHovering
        }
    }

    func togglePin() {
        isPinned.toggle()

        if !isPinned {
            // Stay open until the pointer leaves, like a click-open.
            isForcedOpen = true
            pointerEnteredSinceForcedOpen = isHovering
        }
    }

    func collapse() {
        isPinned = false
        isForcedOpen = false
        suppressesHoverUntilExit = isHovering
    }

    func clearNotificationHistory() {
        notificationHistory = []
    }

    func preferPlayer(_ player: MediaPlayerApp) {
        nowPlayingService.prefer(player)
    }

    /// The panel the launcher highlights and returns to.
    var lastSelectedPanel: IslandPanel {
        UserDefaults.standard.string(forKey: Self.lastPanelKey).flatMap(IslandPanel.init(rawValue:)) ?? .nowPlaying
    }

    private var lastPanelContent: IslandExpandedContent {
        let lastPanel = UserDefaults.standard.string(forKey: Self.lastPanelKey).flatMap(IslandPanel.init(rawValue:))
        return .panel(lastPanel ?? .nowPlaying)
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

        if notification.style != .media {
            notificationHistory.insert(notification, at: 0)

            if notificationHistory.count > Self.maxHistoryCount {
                notificationHistory.removeLast(notificationHistory.count - Self.maxHistoryCount)
            }
        }

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
        activeNotification = notification

        if isHovering {
            notificationDismissTask?.cancel()
            notificationDismissTask = nil
        } else {
            scheduleDismiss(of: notification)
        }
    }

    private func scheduleDismiss(of notification: DynamicIslandNotification) {
        notificationDismissTask?.cancel()

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

    private func handleSystemBanner(_ banner: SystemNotificationBanner) {
        guard preferences.showsSystemNotifications else { return }

        let app = banner.appName.flatMap(Self.application(named:))

        post(
            DynamicIslandNotification(
                caption: banner.appName,
                title: banner.title,
                message: banner.message,
                systemImage: "bell.badge.fill",
                style: .system,
                image: app?.icon,
                sourceAppURL: app?.url
            )
        )
    }

    /// Resolves the app a banner names, preferring a running instance.
    private static func application(named name: String) -> (icon: NSImage, url: URL)? {
        if let running = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name }),
           let url = running.bundleURL {
            return (running.icon ?? NSWorkspace.shared.icon(forFile: url.path), url)
        }

        let candidates = ["/Applications", "/System/Applications", "/System/Applications/Utilities"]
            .map { URL(fileURLWithPath: $0).appendingPathComponent("\(name).app") }

        guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            return nil
        }

        return (NSWorkspace.shared.icon(forFile: url.path), url)
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

        if isEnabled && preferences.showsSystemNotifications {
            systemNotifications.start()
        } else {
            systemNotifications.stop()
        }

        updateShortcuts()

        if !isEnabled {
            clearNotifications()
            hoverEndTask?.cancel()
            hoverEndTask = nil
            isHovering = false
            isPinned = false
            isForcedOpen = false
            presenter?.hide()
        } else {
            presenter?.refresh()
        }
    }
}

// MARK: - Shortcuts

private extension DynamicIslandViewModel {
    /// ⌥⌘-letter shortcuts open each panel; registered once and enabled only
    /// while the island and the shortcut setting are on.
    func updateShortcuts() {
        let names = IslandPanel.allCases.map(\.shortcutName)

        if !hasRegisteredShortcuts {
            hasRegisteredShortcuts = true

            for panel in IslandPanel.allCases {
                KeyboardShortcuts.onKeyUp(for: panel.shortcutName) { [weak self] in
                    Task { @MainActor in
                        self?.open(panel)
                    }
                }
            }
        }

        if isEnabled && preferences.panelShortcutsEnabled {
            KeyboardShortcuts.enable(names)
        } else {
            KeyboardShortcuts.disable(names)
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

#if DEBUG
// MARK: - Demo launch options (Debug builds only)

extension DynamicIslandViewModel {
    /// Puts the island in a given state from launch arguments so CI can take
    /// screenshots without media players, notifications or a pointer, e.g.
    /// `-DeskCastDemoPanel system -DeskCastDemoTrack YES -DeskCastDemoTimer 5`.
    func applyDemoLaunchOptions() {
        let defaults = UserDefaults.standard

        if defaults.bool(forKey: "DeskCastDemoTrack") {
            // Keep the real service from replacing the demo track.
            nowPlayingService.stop()
            let snapshot = MediaPlayerTrackSnapshot(
                player: .spotify,
                trackID: "demo",
                title: "I Was Made For Lovin' You",
                artist: "KISS",
                album: "Dynasty",
                duration: 271,
                elapsed: 208,
                isPlaying: true,
                artworkURL: nil
            )
            nowPlaying = NowPlayingInfo(snapshot: snapshot)
            hasReceivedNowPlaying = true
        }

        let timerMinutes = defaults.integer(forKey: "DeskCastDemoTimer")
        if timerMinutes > 0 {
            timer.start(minutes: timerMinutes)
        }

        if let message = defaults.string(forKey: "DeskCastDemoNotification") {
            post(
                DynamicIslandNotification(
                    caption: "Messages",
                    title: "Ayşe",
                    message: message,
                    systemImage: "message.fill",
                    style: .system
                )
            )
        }

        if let rawPanel = defaults.string(forKey: "DeskCastDemoPanel") {
            if rawPanel == "launcher" {
                expandedContent = .launcher
            } else if let panel = IslandPanel(rawValue: rawPanel) {
                select(panel)
            }

            isPinned = true
        }
    }
}
#endif
