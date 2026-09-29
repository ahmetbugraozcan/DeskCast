import Foundation

// MARK: - Idle content

/// The next calendar event as idle content; `isSoon` flips as it comes
/// within the hour, so the island re-evaluates what to show.
struct IdleCalendarEvent: Equatable {
    let event: IslandCalendarEvent
    let isSoon: Bool
}

extension DynamicIslandViewModel {
    /// Claude's 5-hour limit takes over the automatic island from this share.
    static let claudeUsageAlertFraction = 0.7

    /// What the closed island shows when no activity is going on.
    var idleMode: DynamicIslandMode? {
        switch preferences.idleContent {
        case .nothing, .music: nil
        case .battery: batteryStatus == nil ? nil : .compactBattery
        case .weather: idleWeather == nil ? nil : .compactWeather
        case .nextEvent: idleEvent == nil ? nil : .compactEvent
        case .claudeUsage: idleClaudeUsage == nil ? nil : .compactClaude
        case .automatic: automaticIdleMode
        }
    }

    /// A meeting within the hour, then Claude's limit running out, then low
    /// battery, then the weather; a later meeting or the limit otherwise.
    private var automaticIdleMode: DynamicIslandMode? {
        if idleEvent?.isSoon == true {
            return .compactEvent
        }
        if let idleClaudeUsage, idleClaudeUsage >= Self.claudeUsageAlertFraction {
            return .compactClaude
        }
        if let batteryStatus, batteryStatus.level <= 20, !batteryStatus.isPluggedIn {
            return .compactBattery
        }
        if idleWeather != nil {
            return .compactWeather
        }
        if idleEvent != nil {
            return .compactEvent
        }
        return idleClaudeUsage == nil ? nil : .compactClaude
    }
}
