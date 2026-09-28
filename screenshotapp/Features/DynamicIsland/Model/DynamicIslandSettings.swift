import Foundation

struct DynamicIslandSettingsSnapshot: Equatable {
    let showsNowPlaying: Bool
    let showsTrackChanges: Bool
    let showsAppNotifications: Bool
    let showsBatteryEvents: Bool
    let expandsOnHover: Bool
    let notificationDurationSeconds: Int
}

enum DynamicIslandSettings {
    enum Keys {
        static let showsNowPlaying = "dynamicIsland.showsNowPlaying"
        static let showsTrackChanges = "dynamicIsland.showsTrackChanges"
        static let showsAppNotifications = "dynamicIsland.showsAppNotifications"
        static let showsBatteryEvents = "dynamicIsland.showsBatteryEvents"
        static let expandsOnHover = "dynamicIsland.expandsOnHover"
        static let notificationDurationSeconds = "dynamicIsland.notificationDurationSeconds"
    }

    static let notificationDurationRange = 2...10

    static let defaultShowsNowPlaying = true
    static let defaultShowsTrackChanges = true
    static let defaultShowsAppNotifications = true
    static let defaultShowsBatteryEvents = true
    static let defaultExpandsOnHover = true
    static let defaultNotificationDurationSeconds = 4

    static func registerDefaults(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: defaultValues)
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
            Keys.showsBatteryEvents: defaultShowsBatteryEvents,
            Keys.expandsOnHover: defaultExpandsOnHover,
            Keys.notificationDurationSeconds: defaultNotificationDurationSeconds
        ]
    }

    static func snapshot(from defaults: UserDefaults = .standard) -> DynamicIslandSettingsSnapshot {
        DynamicIslandSettingsSnapshot(
            showsNowPlaying: defaults.bool(forKey: Keys.showsNowPlaying),
            showsTrackChanges: defaults.bool(forKey: Keys.showsTrackChanges),
            showsAppNotifications: defaults.bool(forKey: Keys.showsAppNotifications),
            showsBatteryEvents: defaults.bool(forKey: Keys.showsBatteryEvents),
            expandsOnHover: defaults.bool(forKey: Keys.expandsOnHover),
            notificationDurationSeconds: clampedNotificationDuration(
                defaults.integer(forKey: Keys.notificationDurationSeconds)
            )
        )
    }

    static func clampedNotificationDuration(_ value: Int) -> Int {
        min(max(value, notificationDurationRange.lowerBound), notificationDurationRange.upperBound)
    }
}
