import Foundation

/// How the collapsed island opens.
enum IslandOpenMode: String, CaseIterable, Identifiable {
    /// Opens only on click (or a shortcut / side button).
    case click
    /// Opens when the pointer rests on it.
    case hover
    /// Invisible while collapsed; the pointer reveals and opens it.
    case hiddenUntilHover

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .click: "island.settings.open.click"
        case .hover: "island.settings.open.hover"
        case .hiddenUntilHover: "island.settings.open.hiddenUntilHover"
        }
    }

    var systemImage: String {
        switch self {
        case .click: "cursorarrow.click"
        case .hover: "arrow.up.left.and.arrow.down.right"
        case .hiddenUntilHover: "eye.slash"
        }
    }

    var expandsOnHover: Bool { self != .click }
}

/// What the closed island shows when nothing else is going on.
enum IslandIdleContent: String, CaseIterable, Identifiable {
    case nothing
    case battery
    case music

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .nothing: "island.settings.idle.nothing"
        case .battery: "island.settings.idle.battery"
        case .music: "island.settings.idle.music"
        }
    }

    var systemImage: String {
        switch self {
        case .nothing: "capsule"
        case .battery: "battery.75percent"
        case .music: "music.note"
        }
    }
}

/// Which page the island shows when it opens again.
enum IslandReopenTarget: String, CaseIterable, Identifiable {
    case lastPanel
    case launcher

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .lastPanel: "island.settings.reopen.lastPanel"
        case .launcher: "island.settings.reopen.launcher"
        }
    }
}

/// Which screen hosts the island.
enum IslandDisplayTarget: String, CaseIterable, Identifiable {
    /// The notched screen when there is one, otherwise the menu bar screen.
    case automatic
    case builtIn
    case main

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .automatic: "island.settings.display.automatic"
        case .builtIn: "island.settings.display.builtIn"
        case .main: "island.settings.display.main"
        }
    }

    var systemImage: String {
        switch self {
        case .automatic: "rectangle.on.rectangle"
        case .builtIn: "laptopcomputer"
        case .main: "display"
        }
    }
}

struct DynamicIslandSettingsSnapshot: Equatable {
    var idleContent = DynamicIslandSettings.defaultIdleContent
    var showsTrackChanges = DynamicIslandSettings.defaultShowsTrackChanges
    var showsAppNotifications = DynamicIslandSettings.defaultShowsAppNotifications
    var showsSystemNotifications = DynamicIslandSettings.defaultShowsSystemNotifications
    var showsBatteryEvents = DynamicIslandSettings.defaultShowsBatteryEvents
    var showsEventReminders = DynamicIslandSettings.defaultShowsEventReminders
    var openMode = DynamicIslandSettings.defaultOpenMode
    var hoverDelay = DynamicIslandSettings.defaultHoverDelay
    var closeDelay = DynamicIslandSettings.defaultCloseDelay
    var reopenTarget = DynamicIslandSettings.defaultReopenTarget
    var gesturesEnabled = DynamicIslandSettings.defaultGesturesEnabled
    var hapticsEnabled = DynamicIslandSettings.defaultHapticsEnabled
    var hidesInFullScreen = DynamicIslandSettings.defaultHidesInFullScreen
    var displayTarget = DynamicIslandSettings.defaultDisplayTarget
    var showsInCaptures = DynamicIslandSettings.defaultShowsInCaptures
    var showsOutline = DynamicIslandSettings.defaultShowsOutline
    var panelShortcutsEnabled = DynamicIslandSettings.defaultPanelShortcutsEnabled
    var showsSideButtons = DynamicIslandSettings.defaultShowsSideButtons
    var notificationDurationSeconds = DynamicIslandSettings.defaultNotificationDurationSeconds
    /// Launcher order; every panel appears exactly once.
    var panelOrder: [IslandPanel] = IslandPanel.allCases
    var hiddenPanels: Set<IslandPanel> = []

    /// Panels shown in the launcher, in the user's order.
    var visiblePanels: [IslandPanel] {
        panelOrder.filter { !hiddenPanels.contains($0) }
    }
}

enum DynamicIslandSettings {
    enum Keys {
        static let idleContent = "dynamicIsland.idleContent"
        static let showsTrackChanges = "dynamicIsland.showsTrackChanges"
        static let showsAppNotifications = "dynamicIsland.showsAppNotifications"
        static let showsSystemNotifications = "dynamicIsland.showsSystemNotifications"
        static let showsBatteryEvents = "dynamicIsland.showsBatteryEvents"
        static let showsEventReminders = "dynamicIsland.showsEventReminders"
        static let openMode = "dynamicIsland.openMode"
        static let hoverDelay = "dynamicIsland.hoverDelay"
        static let closeDelay = "dynamicIsland.closeDelay"
        static let reopenTarget = "dynamicIsland.reopenTarget"
        static let gesturesEnabled = "dynamicIsland.gesturesEnabled"
        static let hapticsEnabled = "dynamicIsland.hapticsEnabled"
        static let hidesInFullScreen = "dynamicIsland.hidesInFullScreen"
        static let displayTarget = "dynamicIsland.displayTarget"
        static let showsInCaptures = "dynamicIsland.showsInCaptures"
        static let showsOutline = "dynamicIsland.showsOutline"
        static let panelShortcutsEnabled = "dynamicIsland.panelShortcutsEnabled"
        static let showsSideButtons = "dynamicIsland.showsSideButtons"
        static let panelOrder = "dynamicIsland.panelOrder"
        static let hiddenPanels = "dynamicIsland.hiddenPanels"
        static let scratchpadText = "dynamicIsland.scratchpadText"
        /// The user's own Spotify app Client ID (public with PKCE; not a secret).
        static let spotifyClientID = "dynamicIsland.spotifyClientID"
        static let notificationDurationSeconds = "dynamicIsland.notificationDurationSeconds"
    }

    static let notificationDurationRange = 2...10
    static let hoverDelayRange = 0.0...1.0
    static let closeDelayRange = 0.1...2.0

    static let defaultIdleContent = IslandIdleContent.music
    static let defaultShowsTrackChanges = true
    static let defaultShowsAppNotifications = true
    static let defaultShowsSystemNotifications = true
    static let defaultShowsBatteryEvents = true
    static let defaultShowsEventReminders = true
    static let defaultOpenMode = IslandOpenMode.hover
    static let defaultHoverDelay = 0.15
    /// Grace period before an open island closes once the pointer leaves it.
    static let defaultCloseDelay = 0.5
    static let defaultReopenTarget = IslandReopenTarget.lastPanel
    static let defaultGesturesEnabled = true
    static let defaultHapticsEnabled = true
    static let defaultHidesInFullScreen = true
    static let defaultDisplayTarget = IslandDisplayTarget.automatic
    static let defaultShowsInCaptures = false
    static let defaultShowsOutline = false
    static let defaultPanelShortcutsEnabled = true
    static let defaultShowsSideButtons = true
    /// DeskCast's Spotify app. A PKCE client ID is public (no secret), so it
    /// can ship in the binary; users may still paste their own in Settings.
    static let defaultSpotifyClientID = "561d2c5ed85940bcb9be0a89b71329eb"
    static let defaultNotificationDurationSeconds = 4

    static func registerDefaults(in defaults: UserDefaults = .standard) {
        // Scratchpad text and the Spotify Client ID are user content, so they're
        // registered but never reset.
        defaults.register(
            defaults: defaultValues.merging([
                Keys.scratchpadText: "",
                Keys.spotifyClientID: defaultSpotifyClientID
            ]) { current, _ in current }
        )
    }

    static func resetToDefaults(in defaults: UserDefaults = .standard) {
        for (key, value) in defaultValues {
            defaults.set(value, forKey: key)
        }
    }

    private static var defaultValues: [String: Any] {
        [
            Keys.idleContent: defaultIdleContent.rawValue,
            Keys.showsTrackChanges: defaultShowsTrackChanges,
            Keys.showsAppNotifications: defaultShowsAppNotifications,
            Keys.showsSystemNotifications: defaultShowsSystemNotifications,
            Keys.showsBatteryEvents: defaultShowsBatteryEvents,
            Keys.showsEventReminders: defaultShowsEventReminders,
            Keys.openMode: defaultOpenMode.rawValue,
            Keys.hoverDelay: defaultHoverDelay,
            Keys.closeDelay: defaultCloseDelay,
            Keys.reopenTarget: defaultReopenTarget.rawValue,
            Keys.gesturesEnabled: defaultGesturesEnabled,
            Keys.hapticsEnabled: defaultHapticsEnabled,
            Keys.hidesInFullScreen: defaultHidesInFullScreen,
            Keys.displayTarget: defaultDisplayTarget.rawValue,
            Keys.showsInCaptures: defaultShowsInCaptures,
            Keys.showsOutline: defaultShowsOutline,
            Keys.panelShortcutsEnabled: defaultPanelShortcutsEnabled,
            Keys.showsSideButtons: defaultShowsSideButtons,
            Keys.panelOrder: IslandPanel.allCases.map(\.rawValue),
            Keys.hiddenPanels: [String](),
            Keys.notificationDurationSeconds: defaultNotificationDurationSeconds
        ]
    }

    static func snapshot(from defaults: UserDefaults = .standard) -> DynamicIslandSettingsSnapshot {
        DynamicIslandSettingsSnapshot(
            idleContent: enumValue(defaults, Keys.idleContent, default: defaultIdleContent),
            showsTrackChanges: defaults.bool(forKey: Keys.showsTrackChanges),
            showsAppNotifications: defaults.bool(forKey: Keys.showsAppNotifications),
            showsSystemNotifications: defaults.bool(forKey: Keys.showsSystemNotifications),
            showsBatteryEvents: defaults.bool(forKey: Keys.showsBatteryEvents),
            showsEventReminders: defaults.bool(forKey: Keys.showsEventReminders),
            openMode: enumValue(defaults, Keys.openMode, default: defaultOpenMode),
            hoverDelay: clampedHoverDelay(defaults.double(forKey: Keys.hoverDelay)),
            closeDelay: clampedCloseDelay(defaults.double(forKey: Keys.closeDelay)),
            reopenTarget: enumValue(defaults, Keys.reopenTarget, default: defaultReopenTarget),
            gesturesEnabled: defaults.bool(forKey: Keys.gesturesEnabled),
            hapticsEnabled: defaults.bool(forKey: Keys.hapticsEnabled),
            hidesInFullScreen: defaults.bool(forKey: Keys.hidesInFullScreen),
            displayTarget: enumValue(defaults, Keys.displayTarget, default: defaultDisplayTarget),
            showsInCaptures: defaults.bool(forKey: Keys.showsInCaptures),
            showsOutline: defaults.bool(forKey: Keys.showsOutline),
            panelShortcutsEnabled: defaults.bool(forKey: Keys.panelShortcutsEnabled),
            showsSideButtons: defaults.bool(forKey: Keys.showsSideButtons),
            notificationDurationSeconds: clampedNotificationDuration(
                defaults.integer(forKey: Keys.notificationDurationSeconds)
            ),
            panelOrder: normalizedPanelOrder(defaults.stringArray(forKey: Keys.panelOrder) ?? []),
            hiddenPanels: Set((defaults.stringArray(forKey: Keys.hiddenPanels) ?? []).compactMap(IslandPanel.init(rawValue:)))
        )
    }

    static func clampedNotificationDuration(_ value: Int) -> Int {
        min(max(value, notificationDurationRange.lowerBound), notificationDurationRange.upperBound)
    }

    static func clampedHoverDelay(_ value: Double) -> Double {
        guard value.isFinite else { return defaultHoverDelay }
        return min(max(value, hoverDelayRange.lowerBound), hoverDelayRange.upperBound)
    }

    static func clampedCloseDelay(_ value: Double) -> Double {
        guard value.isFinite else { return defaultCloseDelay }
        return min(max(value, closeDelayRange.lowerBound), closeDelayRange.upperBound)
    }

    /// Keeps the stored order's known panels, drops unknown or repeated ones,
    /// and appends panels added in newer versions at the end.
    static func normalizedPanelOrder(_ rawValues: [String]) -> [IslandPanel] {
        var seen = Set<IslandPanel>()
        let stored = rawValues.compactMap(IslandPanel.init(rawValue:)).filter { seen.insert($0).inserted }
        return stored + IslandPanel.allCases.filter { !seen.contains($0) }
    }

    private static func enumValue<Value: RawRepresentable>(
        _ defaults: UserDefaults,
        _ key: String,
        default defaultValue: Value
    ) -> Value where Value.RawValue == String {
        defaults.string(forKey: key).flatMap(Value.init(rawValue:)) ?? defaultValue
    }
}
