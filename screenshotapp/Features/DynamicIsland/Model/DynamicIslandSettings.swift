import Foundation

struct DynamicIslandSettingsSnapshot: Equatable {
    let showsNowPlaying: Bool
    let showsTrackChanges: Bool
    let showsAppNotifications: Bool
    let showsSystemNotifications: Bool
    let showsBatteryEvents: Bool
    let expandsOnHover: Bool
    let panelShortcutsEnabled: Bool
    let showsSideButtons: Bool
    let notificationDurationSeconds: Int
}

enum DynamicIslandSettings {
    enum Keys {
        static let showsNowPlaying = "dynamicIsland.showsNowPlaying"
        static let showsTrackChanges = "dynamicIsland.showsTrackChanges"
        static let showsAppNotifications = "dynamicIsland.showsAppNotifications"
        static let showsSystemNotifications = "dynamicIsland.showsSystemNotifications"
        static let showsBatteryEvents = "dynamicIsland.showsBatteryEvents"
        static let expandsOnHover = "dynamicIsland.expandsOnHover"
        static let panelShortcutsEnabled = "dynamicIsland.panelShortcutsEnabled"
        static let showsSideButtons = "dynamicIsland.showsSideButtons"
        static let scratchpadText = "dynamicIsland.scratchpadText"
        /// The user's own Spotify app Client ID (public with PKCE; not a secret).
        static let spotifyClientID = "dynamicIsland.spotifyClientID"
        static let notificationDurationSeconds = "dynamicIsland.notificationDurationSeconds"
    }

    static let notificationDurationRange = 2...10

    static let defaultShowsNowPlaying = true
    static let defaultShowsTrackChanges = true
    static let defaultShowsAppNotifications = true
    static let defaultShowsSystemNotifications = true
    static let defaultShowsBatteryEvents = true
    static let defaultExpandsOnHover = true
    static let defaultPanelShortcutsEnabled = true
    static let defaultShowsSideButtons = true
    static let defaultNotificationDurationSeconds = 4

    static func registerDefaults(in defaults: UserDefaults = .standard) {
        // Scratchpad text and the Spotify Client ID are user content, so they're
        // registered but never reset.
        defaults.register(
            defaults: defaultValues.merging([Keys.scratchpadText: "", Keys.spotifyClientID: ""]) { current, _ in current }
        )
    }

    static func resetToDefaults(in defaults: UserDefaults = .standard) {
        for (key, value) in defaultValues {
            defaults.set(value, forKey: key)
        }
    }

    private static var defaultValues: [String: Any] {
        [
            Keys.showsNowPlaying: defaultShowsNowPlaying,
            Keys.showsTrackChanges: defaultShowsTrackChanges,
            Keys.showsAppNotifications: defaultShowsAppNotifications,
            Keys.showsSystemNotifications: defaultShowsSystemNotifications,
            Keys.showsBatteryEvents: defaultShowsBatteryEvents,
            Keys.expandsOnHover: defaultExpandsOnHover,
            Keys.panelShortcutsEnabled: defaultPanelShortcutsEnabled,
            Keys.showsSideButtons: defaultShowsSideButtons,
            Keys.notificationDurationSeconds: defaultNotificationDurationSeconds
        ]
    }

    static func snapshot(from defaults: UserDefaults = .standard) -> DynamicIslandSettingsSnapshot {
        DynamicIslandSettingsSnapshot(
            showsNowPlaying: defaults.bool(forKey: Keys.showsNowPlaying),
            showsTrackChanges: defaults.bool(forKey: Keys.showsTrackChanges),
            showsAppNotifications: defaults.bool(forKey: Keys.showsAppNotifications),
            showsSystemNotifications: defaults.bool(forKey: Keys.showsSystemNotifications),
            showsBatteryEvents: defaults.bool(forKey: Keys.showsBatteryEvents),
            expandsOnHover: defaults.bool(forKey: Keys.expandsOnHover),
            panelShortcutsEnabled: defaults.bool(forKey: Keys.panelShortcutsEnabled),
            showsSideButtons: defaults.bool(forKey: Keys.showsSideButtons),
            notificationDurationSeconds: clampedNotificationDuration(
                defaults.integer(forKey: Keys.notificationDurationSeconds)
            )
        )
    }

    static func clampedNotificationDuration(_ value: Int) -> Int {
        min(max(value, notificationDurationRange.lowerBound), notificationDurationRange.upperBound)
    }
}
