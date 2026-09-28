import AppKit
import Foundation
import Testing
@testable import screenshotapp

@MainActor
private final class FakeNowPlayingService: NowPlayingProviding {
    var onChange: ((NowPlayingInfo?) -> Void)?
    private(set) var isStarted = false
    private(set) var sentCommands: [(MediaCommand, MediaPlayerApp)] = []

    func start() { isStarted = true }
    func stop() { isStarted = false }
    func refresh() {}
    func send(_ command: MediaCommand, to player: MediaPlayerApp) {
        sentCommands.append((command, player))
    }
    func prefer(_ player: MediaPlayerApp) {}

    func emit(_ info: NowPlayingInfo?) {
        onChange?(info)
    }
}

@MainActor
private final class FakeBatteryMonitor: BatteryMonitoring {
    var onChange: ((BatteryStatus) -> Void)?
    var status: BatteryStatus?

    func start() {}
    func stop() {}
    func currentStatus() -> BatteryStatus? { status }

    func emit(_ status: BatteryStatus) {
        self.status = status
        onChange?(status)
    }
}

@MainActor
private final class FakeSystemNotificationMonitor: SystemNotificationMonitoring {
    var onBanner: ((SystemNotificationBanner) -> Void)?
    var isAuthorized = true
    private(set) var isStarted = false

    func start() { isStarted = true }
    func stop() { isStarted = false }

    func emit(_ banner: SystemNotificationBanner) {
        onBanner?(banner)
    }
}

@MainActor
private final class FakeIslandPresenter: DynamicIslandPresenting {
    var isVisible = true
    private(set) var refreshCount = 0
    private(set) var hideCount = 0

    func refresh() { refreshCount += 1 }
    func hide() { hideCount += 1 }
}

@MainActor
private struct StubIslandSettings: DynamicIslandSettingsReading, ToolboxSettingsReading {
    var isEnabled = true
    var expandsOnHover = true

    func dynamicIslandSettings() -> DynamicIslandSettingsSnapshot {
        DynamicIslandSettingsSnapshot(
            showsNowPlaying: true,
            showsTrackChanges: true,
            showsAppNotifications: true,
            showsSystemNotifications: true,
            showsBatteryEvents: true,
            expandsOnHover: expandsOnHover,
            panelShortcutsEnabled: false,
            showsSideButtons: true,
            notificationDurationSeconds: 4
        )
    }

    func isToolEnabled(_ tool: ToolboxToolID) -> Bool {
        tool == .dynamicIsland ? isEnabled : false
    }
}

@MainActor
private func track(_ id: String, isPlaying: Bool = true, elapsed: TimeInterval = 10) -> NowPlayingInfo {
    NowPlayingInfo(
        snapshot: MediaPlayerTrackSnapshot(
            player: .spotify,
            trackID: id,
            title: "Title \(id)",
            artist: "Artist",
            album: "Album",
            duration: 200,
            elapsed: elapsed,
            isPlaying: isPlaying,
            artworkURL: nil
        ),
        capturedAt: Date(timeIntervalSinceReferenceDate: 1_000)
    )
}

@MainActor
struct DynamicIslandViewModelTests {
    private let nowPlaying = FakeNowPlayingService()
    private let battery = FakeBatteryMonitor()
    private let presenter = FakeIslandPresenter()
    private let systemNotifications = FakeSystemNotificationMonitor()

    private func makeViewModel(settings: StubIslandSettings? = nil) -> DynamicIslandViewModel {
        let settings = settings ?? StubIslandSettings()
        let viewModel = DynamicIslandViewModel(
            nowPlayingService: nowPlaying,
            batteryMonitor: battery,
            systemNotifications: systemNotifications,
            settings: settings
        )
        viewModel.presenter = presenter
        viewModel.start()
        return viewModel
    }

    @Test func startsSourcesAndShowsPanelWhenEnabled() {
        let viewModel = makeViewModel()

        #expect(viewModel.isEnabled)
        #expect(nowPlaying.isStarted)
        #expect(presenter.refreshCount == 1)
        #expect(viewModel.mode == .idle)
    }

    @Test func disabledToolHidesPanelAndStopsSources() {
        let viewModel = makeViewModel(settings: StubIslandSettings(isEnabled: false))

        #expect(!viewModel.isEnabled)
        #expect(!nowPlaying.isStarted)
        #expect(presenter.hideCount == 1)
        #expect(!viewModel.postToast("Copied", systemImage: "checkmark", style: .success))
    }

    @Test func playingTrackShowsCompactMediaAndHoverExpands() {
        let viewModel = makeViewModel()

        nowPlaying.emit(track("a"))
        #expect(viewModel.mode == .compactMedia)

        viewModel.setHovering(true)
        #expect(viewModel.mode == .expanded)
    }

    @Test func clickExpandsWhenHoverExpansionIsOff() {
        let viewModel = makeViewModel(settings: StubIslandSettings(expandsOnHover: false))
        nowPlaying.emit(track("a"))

        viewModel.setHovering(true)
        #expect(viewModel.mode == .compactMedia)

        viewModel.toggleExpanded()
        #expect(viewModel.mode == .expanded)
    }

    @Test func firstTrackIsSilentButTrackChangePostsBanner() {
        let viewModel = makeViewModel()

        nowPlaying.emit(track("a"))
        #expect(viewModel.activeNotification == nil)

        nowPlaying.emit(track("b"))
        #expect(viewModel.mode == .notification)
        #expect(viewModel.activeNotification?.style == .media)
        #expect(viewModel.activeNotification?.title == "Title b")
    }

    @Test func toastsRouteIntoIslandOnlyWhilePanelIsVisible() {
        let viewModel = makeViewModel()

        presenter.isVisible = false
        #expect(!viewModel.postToast("Copied", systemImage: "checkmark", style: .success))

        presenter.isVisible = true
        #expect(viewModel.postToast("Copied", systemImage: "checkmark", style: .success))
        #expect(viewModel.activeNotification?.message == "Copied")
    }

    @Test func pluggingInChargerPostsBatteryBanner() {
        battery.status = BatteryStatus(level: 50, isCharging: false, isPluggedIn: false)
        let viewModel = makeViewModel()

        battery.emit(BatteryStatus(level: 50, isCharging: true, isPluggedIn: true))

        #expect(viewModel.activeNotification?.style == .battery)
        #expect(viewModel.activeNotification?.progress == 0.5)
    }

    @Test func otherAppBannerIsMirroredAndHeldWhileHovered() {
        let viewModel = makeViewModel()
        #expect(systemNotifications.isStarted)

        systemNotifications.emit(SystemNotificationBanner(appName: "DeskCastTestApp", title: "Ayşe", message: "Selam"))

        #expect(viewModel.mode == .notification)
        #expect(viewModel.activeNotification?.style == .system)
        #expect(viewModel.activeNotification?.caption == "DeskCastTestApp")
        #expect(viewModel.activeNotification?.title == "Ayşe")

        // Hovering keeps the banner on screen instead of expanding.
        viewModel.setHovering(true)
        #expect(viewModel.mode == .notification)

        viewModel.handleTap()
        #expect(viewModel.activeNotification == nil)
    }

    @Test func sideButtonOpensPanelAndOutsideClickClosesIt() {
        let viewModel = makeViewModel()

        viewModel.open(.system)
        #expect(viewModel.mode == .expanded)
        #expect(viewModel.expandedContent == .panel(.system))

        // Pointer movement outside doesn't close it before it ever entered…
        viewModel.setHovering(false)
        #expect(viewModel.mode == .expanded)

        // …but a click elsewhere does.
        viewModel.handleOutsideClick()
        #expect(viewModel.mode == .idle)
    }

    @Test func pinnedIslandIgnoresOutsideClicks() {
        let viewModel = makeViewModel()

        viewModel.open(.timer)
        viewModel.togglePin()
        viewModel.handleOutsideClick()
        #expect(viewModel.mode == .expanded)

        viewModel.collapse()
        #expect(viewModel.mode == .idle)
    }

    @Test func runningTimerShowsCompactTimerAndNotifiesOnReset() {
        let viewModel = makeViewModel()

        viewModel.timer.start(minutes: 5)
        #expect(viewModel.mode == .compactTimer)
        #expect(viewModel.timer.remaining() <= 300)

        viewModel.timer.reset()
        #expect(viewModel.mode == .idle)
    }

    @Test func postedNotificationsAreKeptInHistory() {
        let viewModel = makeViewModel()

        #expect(viewModel.postToast("Copied", systemImage: "checkmark", style: .success))
        #expect(viewModel.notificationHistory.count == 1)

        viewModel.clearNotificationHistory()
        #expect(viewModel.notificationHistory.isEmpty)
    }

    @Test func playPauseSendsCommandAndFlipsStateOptimistically() {
        let viewModel = makeViewModel()
        nowPlaying.emit(track("a", isPlaying: true))

        viewModel.togglePlayPause()

        #expect(nowPlaying.sentCommands.count == 1)
        #expect(nowPlaying.sentCommands.first?.0 == .togglePlayPause)
        #expect(viewModel.nowPlaying?.isPlaying == false)
    }
}

@MainActor
struct NowPlayingInfoTests {
    @Test func elapsedExtrapolatesOnlyWhilePlaying() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        let later = start.addingTimeInterval(5)

        #expect(track("a", isPlaying: true).elapsed(at: later) == 15)
        #expect(track("a", isPlaying: false).elapsed(at: later) == 10)
    }

    @Test func elapsedIsClampedToDuration() {
        let info = track("a", isPlaying: true, elapsed: 199)
        let muchLater = Date(timeIntervalSinceReferenceDate: 1_000 + 60)

        #expect(info.elapsed(at: muchLater) == 200)
        #expect(info.progress(at: muchLater) == 1)
    }

    @Test func notificationDurationIsClamped() {
        #expect(DynamicIslandSettings.clampedNotificationDuration(0) == DynamicIslandSettings.notificationDurationRange.lowerBound)
        #expect(DynamicIslandSettings.clampedNotificationDuration(99) == DynamicIslandSettings.notificationDurationRange.upperBound)
        #expect(DynamicIslandSettings.clampedNotificationDuration(5) == 5)
    }

    @Test func settingsRegisterAndResetDefaults() throws {
        let suiteName = "DynamicIslandSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        DynamicIslandSettings.registerDefaults(in: defaults)
        defaults.set(false, forKey: DynamicIslandSettings.Keys.showsNowPlaying)
        defaults.set(42, forKey: DynamicIslandSettings.Keys.notificationDurationSeconds)
        #expect(DynamicIslandSettings.snapshot(from: defaults).notificationDurationSeconds == 10)

        DynamicIslandSettings.resetToDefaults(in: defaults)
        let snapshot = DynamicIslandSettings.snapshot(from: defaults)

        #expect(snapshot.showsNowPlaying == DynamicIslandSettings.defaultShowsNowPlaying)
        #expect(snapshot.notificationDurationSeconds == DynamicIslandSettings.defaultNotificationDurationSeconds)

        defaults.removePersistentDomain(forName: suiteName)
    }
}

struct LyricsParsingTests {
    @Test func parsesSyncedLinesInTimeOrder() throws {
        let source = """
        [00:12.50] Second line
        [00:03.00][00:30.00] Chorus
        [ar:Someone]
        """

        let lyrics = try #require(LyricsService.parseLRC(source))

        #expect(lyrics.isSynced)
        #expect(lyrics.lines.map(\.text) == ["Chorus", "Second line", "Chorus"])
        #expect(lyrics.lines.first?.time == 3)
    }

    @Test func currentLineFollowsElapsedTime() throws {
        let lyrics = try #require(LyricsService.parseLRC("[00:01.00] a\n[00:05.00] b\n[00:09.00] c"))

        #expect(lyrics.currentLineIndex(at: 0) == nil)
        #expect(lyrics.currentLineIndex(at: 6) == 1)
        #expect(lyrics.currentLineIndex(at: 60) == 2)
    }

    @Test func textWithoutTimestampsIsNotSyncedLyrics() {
        #expect(LyricsService.parseLRC("just words\nno tags") == nil)
    }
}
