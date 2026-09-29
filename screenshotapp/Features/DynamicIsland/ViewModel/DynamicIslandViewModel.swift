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
    @Published private(set) var nowPlaying: NowPlayingInfo? {
        didSet { notePlaybackStateChange(from: oldValue) }
    }
    @Published private(set) var activeNotification: DynamicIslandNotification?
    @Published private(set) var isHovering = false
    /// The pointer has rested on the island for the hover delay.
    @Published private(set) var isHoverActivated = false
    /// Sticky open from the pin button; only the pin/collapse buttons close it.
    @Published private(set) var isPinned = false
    /// Opened by a click or shortcut; closes on an outside click, or when the
    /// pointer leaves after having entered.
    @Published private(set) var isForcedOpen = false
    /// A window started from the island (e.g. an open panel) is up; closing
    /// the island underneath it would lose the user's context.
    @Published private(set) var isHeldOpen = false
    @Published private(set) var expandedContent: IslandExpandedContent
    @Published private(set) var notificationHistory: [DynamicIslandNotification] = []
    @Published private(set) var geometry = DynamicIslandGeometry.fallback
    @Published private(set) var isEnabled = false
    @Published private(set) var preferences: DynamicIslandSettingsSnapshot
    /// Current weather for the closed island, pushed by `WeatherViewModel`
    /// while the idle content is weather.
    @Published private(set) var idleWeather: WeatherReport?
    /// A Focus is on and the Focus indicator setting is on.
    @Published private(set) var isFocusActive = false
    /// Claude Code / Codex turns in progress, oldest first.
    @Published private(set) var agentSessions: [AgentSession] = []
    /// The activity the user picked for the closed island; `nil` shows them
    /// automatically, with a running timer beside music or an agent.
    @Published private(set) var activityChoice: IslandActivity?

    weak var presenter: DynamicIslandPresenting?

    private let nowPlayingService: NowPlayingProviding
    private let batteryMonitor: BatteryMonitoring
    private let systemNotifications: SystemNotificationMonitoring
    private let settings: DynamicIslandSettingsReading & ToolboxSettingsReading
    private let historyStore: NotificationHistoryPersisting?
    private var pendingNotifications: [DynamicIslandNotification] = []
    private var notificationDismissTask: Task<Void, Never>?
    private var hoverEndTask: Task<Void, Never>?
    private var hoverActivationTask: Task<Void, Never>?
    private var lastBatteryStatus: BatteryStatus?
    private var hasReceivedNowPlaying = false
    /// When playback last went from playing to paused.
    private var pausedAt: Date?
    private var pausedLingerTask: Task<Void, Never>?
    private var defaultsObserver: AnyCancellable?
    private var timerObserver: AnyCancellable?
    private var pointerEnteredSinceForcedOpen = false
    /// After the collapse button, ignore hover until the pointer leaves once.
    private var suppressesHoverUntilExit = false
    private var hasRegisteredShortcuts = false
    /// The page shown before an opening jumped to an activity's page; the
    /// next plain opening returns to it, so "last panel" stays the user's.
    private var contentBeforeActivity: IslandExpandedContent?

    let timer: IslandTimerViewModel

    private static let maxQueuedNotifications = 4
    /// How long a paused track stays in the closed island.
    static let pausedMediaLinger: TimeInterval = 300
    private static let hoverEndDelay: Duration = .milliseconds(160)
    static let actionBannerSeconds = 15
    private static let lowBatteryThresholds = [20, 10]
    private static let maxHistoryCount = 50
    private static let lastPanelKey = "dynamicIsland.lastPanel"

    init(
        nowPlayingService: NowPlayingProviding,
        batteryMonitor: BatteryMonitoring,
        systemNotifications: SystemNotificationMonitoring,
        timer: IslandTimerViewModel? = nil,
        historyStore: NotificationHistoryPersisting? = nil,
        settings: DynamicIslandSettingsReading & ToolboxSettingsReading
    ) {
        self.timer = timer ?? IslandTimerViewModel()
        self.nowPlayingService = nowPlayingService
        self.batteryMonitor = batteryMonitor
        self.systemNotifications = systemNotifications
        self.settings = settings
        self.historyStore = historyStore
        notificationHistory = historyStore?.load() ?? []
        let initialPreferences = settings.dynamicIslandSettings()
        preferences = initialPreferences
        expandedContent = .panel(Self.storedLastPanel(visible: initialPreferences.visiblePanels))

        nowPlayingService.onChange = { [weak self] info in
            self?.handleNowPlayingChange(info)
        }
        batteryMonitor.onChange = { [weak self] status in
            self?.handleBatteryChange(status)
        }
        systemNotifications.onBanner = { [weak self] banner in
            self?.handleSystemBanner(banner)
        }
        systemNotifications.onNotificationCenterList = { [weak self] banners in
            self?.importNotificationCenterList(banners)
        }

        // The compact island shows the running timer, so re-render with it.
        timerObserver = self.timer.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
            // `objectWillChange` fires before the timer's state changes.
            DispatchQueue.main.async { self?.pruneActivityChoice() }
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
        if isPinned || isForcedOpen || isHeldOpen {
            return .expanded
        }

        // A banner stays put while hovered so it can be read and clicked.
        if activeNotification != nil {
            return .notification
        }

        if isExpandedByHover {
            return .expanded
        }

        switch primaryActivity {
        case .media: return .compactMedia
        case .agent: return .compactAgent
        case .timer: return .compactTimer
        case nil: break
        }

        if preferences.idleContent == .battery, batteryStatus != nil {
            return .compactBattery
        }

        if preferences.idleContent == .weather, idleWeather != nil {
            return .compactWeather
        }

        if isFocusActive {
            return .compactFocus
        }

        return .idle
    }

    private var isExpandedByHover: Bool {
        isHoverActivated && preferences.openMode.expandsOnHover && !suppressesHoverUntilExit
    }

    /// "Hidden until hover": the collapsed island is invisible; banners still show.
    var hidesCollapsedIsland: Bool {
        preferences.openMode == .hiddenUntilHover && (mode == .idle || mode.isCompact)
    }

    var batteryStatus: BatteryStatus? {
        lastBatteryStatus
    }

    var availablePlayers: [MediaPlayerApp] {
        MediaPlayerApp.allCases.filter(\.isRunning)
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
                scheduleHoverActivation()
            }

            return
        }

        guard isHovering || (isForcedOpen && pointerEnteredSinceForcedOpen), hoverEndTask == nil else {
            return
        }

        // A grace period keeps the island from snapping shut when the pointer
        // brushes the edge while moving between controls; an open island
        // waits the user's close delay.
        let delay: Duration = mode == .expanded ? .seconds(preferences.closeDelay) : Self.hoverEndDelay
        hoverEndTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.hoverEndTask = nil
            self.isHovering = false
            self.hoverActivationTask?.cancel()
            self.hoverActivationTask = nil
            self.isHoverActivated = false
            self.suppressesHoverUntilExit = false

            if self.isForcedOpen, self.pointerEnteredSinceForcedOpen {
                self.isForcedOpen = false
            }

            if let notification = self.activeNotification {
                self.scheduleDismiss(of: notification)
            }
        }
    }

    /// Expanding on hover waits for the pointer to rest for the hover delay, so
    /// passing over the menu bar doesn't pop the island open.
    private func scheduleHoverActivation() {
        hoverActivationTask?.cancel()

        let delay = preferences.hoverDelay

        guard delay > 0 else {
            activateHover()
            return
        }

        hoverActivationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, self.isHovering else { return }
            self.activateHover()
        }
    }

    private func activateHover() {
        hoverActivationTask = nil

        if preferences.openMode.expandsOnHover, mode != .expanded {
            prepareForOpening()
        }

        isHoverActivated = true
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

        if !isForcedOpen, mode != .expanded {
            prepareForOpening()
        }

        isForcedOpen.toggle()
        pointerEnteredSinceForcedOpen = isHovering
    }

    /// A click anywhere outside the island closes a click/shortcut-opened island.
    func handleOutsideClick() {
        guard isForcedOpen, !isPinned else { return }
        isForcedOpen = false
    }

    // MARK: - Gestures

    /// Trackpad/mouse swipes on the island. Returns whether the swipe did
    /// something, so the caller can play haptic feedback and swallow the event.
    @discardableResult
    func handleSwipe(_ direction: IslandSwipeDirection, inTopRow: Bool) -> Bool {
        guard preferences.gesturesEnabled else { return false }

        switch direction {
        case .down:
            guard mode != .expanded else { return false }
            prepareForOpening()
            isForcedOpen = true
            pointerEnteredSinceForcedOpen = isHovering
            return true
        case .up:
            // Inside an open panel, upward scrolls belong to its lists; only the
            // header row closes the island.
            guard mode == .expanded, inTopRow, !isPinned else { return false }
            collapse()
            return true
        case .left, .right:
            guard mode == .compactMedia || (mode == .expanded && expandedContent == .panel(.nowPlaying) && inTopRow) else {
                return false
            }
            // Like flicking cards: swiping left brings the next track.
            if direction == .left {
                nextTrack()
            } else {
                previousTrack()
            }
            return true
        }
    }

    // MARK: - Panels

    func select(_ panel: IslandPanel) {
        contentBeforeActivity = nil
        expandedContent = .panel(panel)
        UserDefaults.standard.set(panel.rawValue, forKey: Self.lastPanelKey)
    }

    func showLauncher() {
        contentBeforeActivity = nil
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

    /// A file drag reached the island: show the Files panel so it can land there.
    /// It closes again once the pointer leaves, like a click-open.
    func beginFileDrag() {
        guard preferences.visiblePanels.contains(.files) else { return }

        select(.files)
        isForcedOpen = true
        pointerEnteredSinceForcedOpen = true
    }

    /// Runs `body` (typically a modal open panel) with the island kept open.
    func holdingOpen<T>(_ body: () -> T) -> T {
        isHeldOpen = true
        defer {
            isHeldOpen = false
            // Back to a click-open island: stays until an outside click or
            // the pointer enters and leaves.
            isForcedOpen = true
            pointerEnteredSinceForcedOpen = isHovering
        }

        return body()
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

    func preferPlayer(_ player: MediaPlayerApp) {
        nowPlayingService.prefer(player)
    }

    /// The panel the launcher highlights and returns to.
    var lastSelectedPanel: IslandPanel {
        Self.storedLastPanel(visible: preferences.visiblePanels)
    }

    private var lastPanelContent: IslandExpandedContent {
        .panel(lastSelectedPanel)
    }

    /// The last opened panel, unless it has since been hidden from the island.
    private static func storedLastPanel(visible: [IslandPanel]) -> IslandPanel {
        let stored = UserDefaults.standard.string(forKey: lastPanelKey).flatMap(IslandPanel.init(rawValue:))

        if let stored, visible.contains(stored) {
            return stored
        }

        return visible.contains(.nowPlaying) ? .nowPlaying : (visible.first ?? .nowPlaying)
    }

    func togglePlayPause() {
        guard let nowPlaying else { return }
        nowPlayingService.send(.togglePlayPause, to: nowPlaying.source)
        // Optimistic flip; the next player notification confirms it.
        self.nowPlaying = nowPlaying.togglingPlayback()
    }

    func nextTrack() {
        guard let nowPlaying else { return }
        nowPlayingService.send(.nextTrack, to: nowPlaying.source)
    }

    func previousTrack() {
        guard let nowPlaying else { return }
        nowPlayingService.send(.previousTrack, to: nowPlaying.source)
    }

    func openPlayer(_ player: MediaPlayerApp? = nil) {
        guard
            let bundleIdentifier = player?.bundleIdentifier ?? nowPlaying?.source.bundleIdentifier,
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
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

            trimAndSaveHistory()
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

        // Banners with a button (e.g. "Join") stay long enough to reach it.
        let seconds = preferences.notificationDurationSeconds
        let duration = Duration.seconds(notification.action == nil ? seconds : max(seconds, Self.actionBannerSeconds))
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
        pruneActivityChoice()

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
            title: info.title.isEmpty ? info.source.displayName : info.title,
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

        post(Self.systemNotification(from: banner))
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
        // The compact battery readout depends on it.
        objectWillChange.send()
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

        // The Now Playing panel needs the player even when the closed island
        // shows something else.
        if isEnabled {
            nowPlayingService.start()
        } else {
            nowPlayingService.stop()
            nowPlaying = nil
            hasReceivedNowPlaying = false
        }

        if isEnabled && (preferences.showsBatteryEvents || preferences.idleContent == .battery) {
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

        // A panel hidden from the island shouldn't stay open.
        if case .panel(let panel) = expandedContent, preferences.hiddenPanels.contains(panel) {
            expandedContent = .launcher
        }

        updateShortcuts()

        if !isEnabled {
            clearNotifications()
            hoverEndTask?.cancel()
            hoverEndTask = nil
            hoverActivationTask?.cancel()
            hoverActivationTask = nil
            isHovering = false
            isHoverActivated = false
            isPinned = false
            isForcedOpen = false
            presenter?.hide()
        } else {
            presenter?.refresh()
        }
    }
}

// MARK: - Media

extension DynamicIslandViewModel {
    /// Music in the closed island: while playing, and for a while after a
    /// pause. A long-paused session (e.g. a forgotten video tab, which stays
    /// in the system now playing session) doesn't keep the island wide.
    var hasMedia: Bool {
        // Weather in the closed island steps aside while music plays.
        guard [.music, .weather].contains(preferences.idleContent), let nowPlaying else { return false }
        guard !nowPlaying.isPlaying else { return true }
        guard let pausedAt else { return false }
        return Date().timeIntervalSince(pausedAt) < Self.pausedMediaLinger
    }

    private func notePlaybackStateChange(from oldValue: NowPlayingInfo?) {
        let wasPlaying = oldValue?.isPlaying == true
        let isPlaying = nowPlaying?.isPlaying == true

        if isPlaying {
            pausedAt = nil
            pausedLingerTask?.cancel()
            pausedLingerTask = nil
        } else if wasPlaying {
            pausedAt = Date()
            pausedLingerTask?.cancel()
            // Re-render once the linger ends so the closed island shrinks.
            pausedLingerTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.pausedMediaLinger))
                guard !Task.isCancelled else { return }
                self?.objectWillChange.send()
                self?.pruneActivityChoice()
            }
        }
    }

    func seek(to seconds: TimeInterval) {
        guard let nowPlaying else { return }
        nowPlayingService.seek(to: seconds, in: nowPlaying.source)
        self.nowPlaying = nowPlaying.seeking(to: seconds)
    }

    /// Sets the playing player's own volume; only scripted players have one.
    func setPlayerVolume(_ volume: Double) {
        guard var nowPlaying, let player = nowPlaying.player else { return }

        let clamped = min(max(volume, 0), 1)
        // Players take whole percents; skip drag steps that change nothing.
        guard Int((clamped * 100).rounded()) != nowPlaying.volume.map({ Int(($0 * 100).rounded()) }) else { return }

        nowPlayingService.setVolume(clamped, for: player)
        nowPlaying.volume = clamped
        self.nowPlaying = nowPlaying
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

        guard isEnabled && preferences.panelShortcutsEnabled else {
            KeyboardShortcuts.disable(names)
            return
        }

        let hidden = preferences.hiddenPanels
        KeyboardShortcuts.enable(IslandPanel.allCases.filter { !hidden.contains($0) }.map(\.shortcutName))
        KeyboardShortcuts.disable(IslandPanel.allCases.filter { hidden.contains($0) }.map(\.shortcutName))
    }
}

// MARK: - Launcher layout & weather

extension DynamicIslandViewModel {
    /// Saves the launcher layout edited in the island: `visibleOrder` is the
    /// new order of shown panels, hidden ones keep their relative order after
    /// them. At least one panel always stays visible. Applied right away so the
    /// grid doesn't flash back to the old order before defaults notify.
    func updatePanelLayout(visibleOrder: [IslandPanel], hidden: Set<IslandPanel>) {
        let shown = visibleOrder.filter { !hidden.contains($0) }
        guard !shown.isEmpty else { return }
        let rest = preferences.panelOrder.filter { !shown.contains($0) }
        let defaults = UserDefaults.standard
        defaults.set((shown + rest).map(\.rawValue), forKey: DynamicIslandSettings.Keys.panelOrder)
        defaults.set(IslandPanel.allCases.filter(hidden.contains).map(\.rawValue), forKey: DynamicIslandSettings.Keys.hiddenPanels)
        applySettingsChange()
    }

    func updateIdleWeather(_ report: WeatherReport?) {
        guard idleWeather != report else { return }
        idleWeather = report
    }

    func clearNotificationHistory() {
        notificationHistory = []
        historyStore?.save([])
    }

    private static func systemNotification(from banner: SystemNotificationBanner, date: Date = Date()) -> DynamicIslandNotification {
        let app = banner.appName.flatMap(Self.application(named:))
        return DynamicIslandNotification(
            date: date,
            caption: banner.appName,
            title: banner.title,
            message: banner.message,
            systemImage: "bell.badge.fill",
            style: .system,
            image: app?.icon,
            sourceAppURL: app?.url
        )
    }

    /// Adds what the open Notification Center lists and the history lacks,
    /// without showing banners for it, and moves entries imported earlier
    /// back to the time the list gives them.
    func importNotificationCenterList(_ banners: [SystemNotificationBanner]) {
        guard isEnabled, preferences.showsSystemNotifications else { return }
        var indexBySignature: [String: Int] = [:]
        for (index, notification) in notificationHistory.enumerated().reversed() {
            indexBySignature[Self.historySignature(notification)] = index
        }
        let now = Date()
        var changed = false
        // Listed newest first; items without a time (or sharing one) get
        // slightly older times so the order survives sorting.
        for (index, banner) in banners.enumerated() {
            let offset = Double(index + 1)
            let date = banner.postedAt.map { $0.addingTimeInterval(-offset / 1_000) } ?? now.addingTimeInterval(-offset)
            let notification = Self.systemNotification(from: banner, date: date)
            if let known = indexBySignature[Self.historySignature(notification)] {
                // Only a real time corrects an entry, and only when it is
                // clearly off (the list rounds to minutes).
                if banner.postedAt != nil, notificationHistory[known].date.timeIntervalSince(date) > 120 {
                    notificationHistory[known].date = date
                    changed = true
                }
            } else {
                notificationHistory.append(notification)
                changed = true
            }
        }
        guard changed else { return }
        notificationHistory.sort { $0.date > $1.date }
        trimAndSaveHistory()
    }

    private func trimAndSaveHistory() {
        if notificationHistory.count > Self.maxHistoryCount {
            notificationHistory.removeLast(notificationHistory.count - Self.maxHistoryCount)
        }
        historyStore?.save(notificationHistory)
    }

    private static func historySignature(_ notification: DynamicIslandNotification) -> String {
        [notification.caption ?? "", notification.title, notification.message ?? ""].joined(separator: "\u{1F}")
    }

    /// Picks the page a fresh opening shows: the activity on screen, when
    /// that setting is on, otherwise the reopen target.
    private func prepareForOpening() {
        if preferences.opensToActivity, let panel = activityPanel, preferences.visiblePanels.contains(panel) {
            if contentBeforeActivity == nil {
                contentBeforeActivity = expandedContent
            }
            expandedContent = .panel(panel)
            return
        }

        let previous = contentBeforeActivity ?? expandedContent
        contentBeforeActivity = nil

        switch preferences.reopenTarget {
        case .lastPanel:
            expandedContent = previous
        case .launcher:
            expandedContent = .launcher
        case .panel(let panel):
            expandedContent = preferences.visiblePanels.contains(panel) ? .panel(panel) : previous
        }
    }

    /// The page of what the closed island is showing, if it is an activity.
    var activityPanel: IslandPanel? {
        mode == .notification ? .notifications : (mode.isCompact ? primaryActivity?.panel : nil)
    }

    // MARK: Activities

    /// Activities going on now, in the automatic order: music, a working
    /// agent, the timer. Media from other apps (a browser video) steps
    /// behind a working agent.
    var availableActivities: [IslandActivity] {
        let order: [IslandActivity] = nowPlaying?.source.player == nil ? [.agent, .media, .timer] : IslandActivity.allCases
        return order.filter { activity in
            switch activity {
            case .media: hasMedia
            case .agent: preferences.showsAgentActivity && !agentSessions.isEmpty
            case .timer: timer.isActive
            }
        }
    }

    /// What the closed island shows: the user's pick while it lasts,
    /// otherwise music, then a working agent, then the timer.
    var primaryActivity: IslandActivity? {
        let available = availableActivities
        if let activityChoice, available.contains(activityChoice) {
            return activityChoice
        }
        return available.first
    }

    /// A running timer rides along on the right when the island shows
    /// activities automatically.
    var showsTimerBeside: Bool {
        activityChoice == nil && timer.isActive && primaryActivity != .timer
    }

    /// The activity chips under the island, when there is a choice to make.
    var showsActivityPicker: Bool {
        availableActivities.count >= 2 && (mode == .expanded || (isHovering && mode.isCompact))
    }

    /// Picks what the closed island shows (`nil`: automatic). In the open
    /// island it also shows that activity's page.
    func chooseActivity(_ activity: IslandActivity?) {
        activityChoice = activity
        if mode == .expanded, let activity, preferences.visiblePanels.contains(activity.panel) {
            select(activity.panel)
        }
    }

    /// A pick lasts only while its activity does.
    func pruneActivityChoice() {
        if let activityChoice, !availableActivities.contains(activityChoice) {
            self.activityChoice = nil
        }
    }

    func updateAgentSessions(_ sessions: [AgentSession]) {
        guard agentSessions != sessions else { return }
        agentSessions = sessions
        pruneActivityChoice()
    }

    func updateFocusActive(_ active: Bool) {
        guard isFocusActive != active else { return }
        isFocusActive = active
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

        if defaults.bool(forKey: "DeskCastDemoStopwatch") {
            timer.panelMode = .stopwatch
        }

        if defaults.bool(forKey: "DeskCastDemoFocus") {
            isFocusActive = true
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

        if let title = defaults.string(forKey: "DeskCastDemoMeeting"),
           let url = URL(string: "https://meet.google.com/abc-defg-hij") {
            let start = Date().addingTimeInterval(4 * 60)
            let event = IslandCalendarEvent(
                id: "demo-meeting",
                title: title,
                start: start,
                end: start.addingTimeInterval(1800),
                isAllDay: false,
                color: .systemBlue,
                meetingLink: MeetingLink(url)
            )
            post(EventReminderMonitor.banner(for: event, now: Date()))
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
