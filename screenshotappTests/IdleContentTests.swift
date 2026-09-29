import AppKit
import Foundation
import Testing
@testable import screenshotapp

@MainActor
struct IdleContentTests {
    private let nowPlaying = FakeNowPlayingService()
    private let battery = FakeBatteryMonitor()
    private let presenter = FakeIslandPresenter()

    private func makeViewModel(_ content: IslandIdleContent = .automatic) -> DynamicIslandViewModel {
        let viewModel = DynamicIslandViewModel(
            nowPlayingService: nowPlaying,
            batteryMonitor: battery,
            systemNotifications: FakeSystemNotificationMonitor(),
            settings: StubIslandSettings { $0.idleContent = content }
        )
        viewModel.presenter = presenter
        viewModel.start()
        return viewModel
    }

    private func event(startingIn seconds: TimeInterval, allDay: Bool = false, now: Date = Date()) -> IslandCalendarEvent {
        IslandCalendarEvent(
            id: UUID().uuidString,
            title: "Daily",
            start: now.addingTimeInterval(seconds),
            end: now.addingTimeInterval(seconds + 1800),
            isAllDay: allDay,
            color: .systemBlue
        )
    }

    @Test func automaticIsTheDefault() {
        #expect(DynamicIslandSettings.defaultIdleContent == .automatic)
        #expect(DynamicIslandSettingsSnapshot().idleContent == .automatic)
    }

    @Test func automaticPicksWhatMattersMost() {
        let viewModel = makeViewModel()
        #expect(viewModel.mode == .idle)

        viewModel.updateIdleClaudeUsage(0.3)
        #expect(viewModel.mode == .compactClaude)

        viewModel.updateIdleWeather(weatherReport())
        #expect(viewModel.mode == .compactWeather)

        viewModel.updateIdleEvent(IdleCalendarEvent(event: event(startingIn: 3 * 3600), isSoon: false))
        #expect(viewModel.mode == .compactWeather)

        viewModel.updateIdleClaudeUsage(0.8)
        #expect(viewModel.mode == .compactClaude)

        viewModel.updateIdleEvent(IdleCalendarEvent(event: event(startingIn: 600), isSoon: true))
        #expect(viewModel.mode == .compactEvent)

        // Music still wins while it plays.
        nowPlaying.emit(track("a"))
        #expect(viewModel.mode == .compactMedia)
    }

    @Test func automaticShowsLowBatteryBeforeWeather() {
        battery.status = BatteryStatus(level: 15, isCharging: false, isPluggedIn: false)
        let viewModel = makeViewModel()
        viewModel.updateIdleWeather(weatherReport())
        #expect(viewModel.mode == .compactBattery)
    }

    @Test func explicitChoicesShowOnlyTheirContent() {
        let events = makeViewModel(.nextEvent)
        events.updateIdleClaudeUsage(0.9)
        #expect(events.mode == .idle)
        events.updateIdleEvent(IdleCalendarEvent(event: event(startingIn: 3 * 3600), isSoon: false))
        #expect(events.mode == .compactEvent)

        let claude = makeViewModel(.claudeUsage)
        claude.updateIdleClaudeUsage(0.1)
        #expect(claude.mode == .compactClaude)
    }

    @Test func nextEventSkipsAllDayStartedAndDistantEvents() {
        let now = Date()
        let events = [
            event(startingIn: -300, now: now),
            event(startingIn: 1800, allDay: true, now: now),
            event(startingIn: 13 * 3600, now: now),
            event(startingIn: 2 * 3600, now: now),
            event(startingIn: 40 * 60, now: now)
        ]

        let next = IdleInfoMonitor.nextEvent(in: events, at: now)
        #expect(next?.event.start == now.addingTimeInterval(40 * 60))
        #expect(next?.isSoon == true)
        #expect(IdleInfoMonitor.nextEvent(in: [events[3]], at: now)?.isSoon == false)
        #expect(IdleInfoMonitor.nextEvent(in: Array(events.prefix(3)), at: now) == nil)
    }

    @Test func eventCountdownWithinTheHourThenStartTime() {
        let now = Date()
        let soon = CompactEventView.when(now.addingTimeInterval(24 * 60 + 10), now: now)
        #expect(soon == AppLocalization.formatted("island.idle.inMinutes", 25))
        let later = now.addingTimeInterval(3 * 3600)
        #expect(CompactEventView.when(later, now: now) == later.formatted(date: .omitted, time: .shortened))
    }

    @Test func theOldMusicDefaultMovesToAutomaticOnce() throws {
        let defaults = try #require(UserDefaults(suiteName: "IdleContentTests-\(UUID().uuidString)"))
        defaults.set("music", forKey: DynamicIslandSettings.Keys.idleContent)
        DynamicIslandSettings.migrateIdleContentToAutomatic(in: defaults)
        // Removed, so the registered default (Automatic) applies.
        #expect(defaults.object(forKey: DynamicIslandSettings.Keys.idleContent) as? String != "music")

        // A later pick of Music sticks.
        defaults.set("music", forKey: DynamicIslandSettings.Keys.idleContent)
        DynamicIslandSettings.migrateIdleContentToAutomatic(in: defaults)
        #expect(defaults.string(forKey: DynamicIslandSettings.Keys.idleContent) == "music")

        let weather = try #require(UserDefaults(suiteName: "IdleContentTests-\(UUID().uuidString)"))
        weather.set("weather", forKey: DynamicIslandSettings.Keys.idleContent)
        DynamicIslandSettings.migrateIdleContentToAutomatic(in: weather)
        #expect(weather.string(forKey: DynamicIslandSettings.Keys.idleContent) == "weather")
    }
}
