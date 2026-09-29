import AppKit
import CoreAudio
import Foundation
import Testing
@testable import screenshotapp

@MainActor
private final class FakeNowPlayingService: NowPlayingProviding {
    var onChange: ((NowPlayingInfo?) -> Void)?
    private(set) var isStarted = false
    private(set) var sentCommands: [(MediaCommand, NowPlayingSource)] = []

    func start() { isStarted = true }
    func stop() { isStarted = false }
    func refresh() {}
    func send(_ command: MediaCommand, to source: NowPlayingSource) {
        sentCommands.append((command, source))
    }
    func seek(to seconds: TimeInterval, in source: NowPlayingSource) {}
    func setVolume(_ volume: Double, for player: MediaPlayerApp) {}
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
    var snapshot = DynamicIslandSettingsSnapshot(hoverDelay: 0, panelShortcutsEnabled: false)

    init(isEnabled: Bool = true, configure: (inout DynamicIslandSettingsSnapshot) -> Void = { _ in }) {
        self.isEnabled = isEnabled
        configure(&snapshot)
    }

    func dynamicIslandSettings() -> DynamicIslandSettingsSnapshot {
        snapshot
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
        let viewModel = makeViewModel(settings: StubIslandSettings { $0.openMode = .click })
        nowPlaying.emit(track("a"))

        viewModel.setHovering(true)
        #expect(viewModel.mode == .compactMedia)

        viewModel.toggleExpanded()
        #expect(viewModel.mode == .expanded)
    }

    @Test func hiddenUntilHoverHidesCollapsedIslandOnly() {
        let viewModel = makeViewModel(settings: StubIslandSettings { $0.openMode = .hiddenUntilHover })
        nowPlaying.emit(track("a"))
        #expect(viewModel.mode == .compactMedia)
        #expect(viewModel.hidesCollapsedIsland)

        viewModel.setHovering(true)
        #expect(viewModel.mode == .expanded)
        #expect(!viewModel.hidesCollapsedIsland)
    }

    @Test func idleContentNothingKeepsMusicOutOfTheClosedIsland() {
        let viewModel = makeViewModel(settings: StubIslandSettings { $0.idleContent = .nothing })
        nowPlaying.emit(track("a"))
        #expect(viewModel.mode == .idle)
        #expect(viewModel.nowPlaying != nil)
    }

    @Test func reopeningOnLauncherStartsOnThePanelGrid() {
        let viewModel = makeViewModel(settings: StubIslandSettings { $0.reopenTarget = .launcher })
        viewModel.select(.timer)

        viewModel.setHovering(true)
        #expect(viewModel.mode == .expanded)
        #expect(viewModel.expandedContent == .launcher)
    }

    @Test func swipesOpenCloseAndSkipTracks() {
        let viewModel = makeViewModel(settings: StubIslandSettings { $0.openMode = .click })
        nowPlaying.emit(track("a"))

        #expect(viewModel.handleSwipe(.left, inTopRow: true))
        #expect(nowPlaying.sentCommands.last?.0 == .nextTrack)

        #expect(viewModel.handleSwipe(.down, inTopRow: false))
        #expect(viewModel.mode == .expanded)

        // Scrolling up inside a panel's content is left to its lists.
        #expect(!viewModel.handleSwipe(.up, inTopRow: false))
        #expect(viewModel.handleSwipe(.up, inTopRow: true))
        #expect(viewModel.mode == .compactMedia)
    }

    @Test func gesturesCanBeTurnedOff() {
        let viewModel = makeViewModel(settings: StubIslandSettings { $0.gesturesEnabled = false })
        #expect(!viewModel.handleSwipe(.down, inTopRow: false))
        #expect(viewModel.mode == .idle)
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
private final class FakeFocusStatus: FocusStatusProviding {
    var access = FocusAccess.allowed
    var isFocused = false

    func requestAccess(_ completion: @escaping (FocusAccess) -> Void) {
        completion(access)
    }
}

@MainActor
private func weatherReport(_ temperature: Double = 19) -> WeatherReport {
    WeatherReport(
        place: WeatherPlace(name: "Istanbul", country: nil, latitude: 41, longitude: 29),
        unit: .celsius,
        temperature: temperature,
        apparentTemperature: nil,
        humidity: nil,
        windSpeed: nil,
        condition: .rain,
        isDay: true,
        high: nil,
        low: nil,
        timeZone: .gmt,
        hourly: [],
        fetchedAt: Date()
    )
}

extension DynamicIslandViewModelTests {
    @Test func focusIndicatorFollowsFocusOnlyWhileTheSettingIsOn() {
        let focus = FakeFocusStatus()
        focus.isFocused = true

        let off = makeViewModel()
        let offMonitor = FocusIndicatorMonitor(service: focus)
        offMonitor.bind(to: off)
        #expect(off.mode == .idle)

        let on = makeViewModel(settings: StubIslandSettings { $0.showsFocusIndicator = true })
        let onMonitor = FocusIndicatorMonitor(service: focus)
        onMonitor.bind(to: on)
        #expect(on.mode == .compactFocus)
    }

    @Test func idleContentOutranksTheFocusMoonAndMusicOutranksWeather() {
        let viewModel = makeViewModel(settings: StubIslandSettings { $0.idleContent = .weather })
        viewModel.updateFocusActive(true)
        #expect(viewModel.mode == .compactFocus)

        viewModel.updateIdleWeather(weatherReport())
        #expect(viewModel.mode == .compactWeather)

        nowPlaying.emit(track("a"))
        #expect(viewModel.mode == .compactMedia)
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

    @Test func closeDelayIsClamped() {
        #expect(DynamicIslandSettings.clampedCloseDelay(0) == DynamicIslandSettings.closeDelayRange.lowerBound)
        #expect(DynamicIslandSettings.clampedCloseDelay(9) == DynamicIslandSettings.closeDelayRange.upperBound)
        #expect(DynamicIslandSettings.clampedCloseDelay(.nan) == DynamicIslandSettings.defaultCloseDelay)
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
        defaults.set(IslandIdleContent.nothing.rawValue, forKey: DynamicIslandSettings.Keys.idleContent)
        defaults.set(["timer", "bogus", "timer"], forKey: DynamicIslandSettings.Keys.panelOrder)
        #expect(DynamicIslandSettings.snapshot(from: defaults).panelOrder.first == .timer)
        #expect(DynamicIslandSettings.snapshot(from: defaults).panelOrder.count == IslandPanel.allCases.count)
        defaults.set(42, forKey: DynamicIslandSettings.Keys.notificationDurationSeconds)
        #expect(DynamicIslandSettings.snapshot(from: defaults).notificationDurationSeconds == 10)

        DynamicIslandSettings.resetToDefaults(in: defaults)
        let snapshot = DynamicIslandSettings.snapshot(from: defaults)

        #expect(snapshot.idleContent == DynamicIslandSettings.defaultIdleContent)
        #expect(snapshot.panelOrder == IslandPanel.allCases)
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

struct AppAudioTapRenderTests {
    /// Runs `render` on a stereo tap buffer and returns the output buffers.
    private func render(tap: [Float], outputChannels: [Int], frames: Int, gain: Float = 0.5) -> [[Float]] {
        let tapData = UnsafeMutablePointer<Float>.allocate(capacity: tap.count)
        tapData.initialize(from: tap, count: tap.count)
        let outData = outputChannels.map { channels in
            let data = UnsafeMutablePointer<Float>.allocate(capacity: channels * frames)
            data.initialize(repeating: -1, count: channels * frames)
            return data
        }
        let input = AudioBufferList.allocate(maximumBuffers: 1)
        let output = AudioBufferList.allocate(maximumBuffers: outputChannels.count)
        defer {
            tapData.deallocate()
            outData.forEach { $0.deallocate() }
            free(input.unsafeMutablePointer)
            free(output.unsafeMutablePointer)
        }

        input[0] = AudioBuffer(
            mNumberChannels: 2,
            mDataByteSize: UInt32(tap.count * MemoryLayout<Float>.size),
            mData: tapData
        )

        for (index, channels) in outputChannels.enumerated() {
            output[index] = AudioBuffer(
                mNumberChannels: UInt32(channels),
                mDataByteSize: UInt32(channels * frames * MemoryLayout<Float>.size),
                mData: outData[index]
            )
        }

        AppAudioTap.render(input: input.unsafePointer, output: output.unsafeMutablePointer, gain: gain)

        return zip(outData, outputChannels).map { data, channels in
            Array(UnsafeBufferPointer(start: data, count: channels * frames))
        }
    }

    @Test func interleavedStereoOutputGetsBothChannels() {
        let out = render(tap: [1, 2, 3, 4], outputChannels: [2], frames: 2)
        #expect(out == [[0.5, 1, 1.5, 2]])
    }

    @Test func perChannelOutputBuffersGetLeftAndRight() {
        let out = render(tap: [1, 2, 3, 4], outputChannels: [1, 1], frames: 2)
        #expect(out == [[0.5, 1.5], [1, 2]])
    }

    @Test func extraOutputChannelsStaySilent() {
        let out = render(tap: [1, 2], outputChannels: [6], frames: 1)
        #expect(out == [[0.5, 1, 0, 0, 0, 0]])
    }
}

struct ClaudePlanUsageTests {
    private let now = Date(timeIntervalSince1970: 1_790_631_200)

    private struct Sample {
        let age: TimeInterval
        let session: Int
        let week: Int
    }

    private func history(_ samples: [Sample]) -> Data {
        let items = samples.map { sample in
            let time = (now.timeIntervalSince1970 - sample.age) * 1000
            return "{\"t\":\(time),\"org\":\"o\",\"u\":{\"fh\":\(sample.session),\"sd\":\(sample.week)}}"
        }
        return Data("{\"version\":2,\"samples\":[\(items.joined(separator: ","))]}".utf8)
    }

    @Test func readsNewestSample() throws {
        let data = history([Sample(age: 600, session: 68, week: 14), Sample(age: 3600, session: 41, week: 10)])
        let usage = try #require(AIUsageService.claudePlanUsage(from: data, now: now))
        #expect(usage.session?.usedFraction == 0.68)
        #expect(usage.weekly?.usedFraction == 0.14)
        #expect(usage.updatedAt == now.addingTimeInterval(-600))
    }

    @Test func dropsSessionOlderThanFiveHours() throws {
        let usage = try #require(AIUsageService.claudePlanUsage(from: history([Sample(age: 6 * 3600, session: 90, week: 30)]), now: now))
        #expect(usage.session == nil)
        #expect(usage.weekly?.usedFraction == 0.3)
    }

    @Test func windowPastItsResetStartsEmpty() {
        let window = AIUsageWindow(usedFraction: 0.16, resetsAt: now.addingTimeInterval(-60))
        #expect(window.current(at: now) == AIUsageWindow(usedFraction: 0, resetsAt: nil))

        let live = AIUsageWindow(usedFraction: 0.16, resetsAt: now.addingTimeInterval(60))
        #expect(live.current(at: now) == live)
    }

    @Test func rejectsMalformedHistory() {
        #expect(AIUsageService.claudePlanUsage(from: Data("{}".utf8), now: now) == nil)
        #expect(AIUsageService.claudePlanUsage(from: history([]), now: now) == nil)
    }
}

struct NowPlayingSourceSelectionTests {
    private func snapshot(_ bundle: String, playing: Bool, volume: Double? = nil) -> MediaPlayerTrackSnapshot {
        MediaPlayerTrackSnapshot(
            source: NowPlayingSource(bundleIdentifier: bundle),
            trackID: bundle,
            title: "Title",
            artist: "Artist",
            album: "",
            duration: 100,
            elapsed: 1,
            isPlaying: playing,
            artworkURL: nil,
            volume: volume
        )
    }

    private func choose(
        scripted: [MediaPlayerTrackSnapshot],
        system: MediaPlayerTrackSnapshot?,
        preferred: MediaPlayerApp? = nil
    ) -> String? {
        MediaPlayerNowPlayingService.choose(
            scripted: scripted,
            system: system,
            preferred: preferred,
            lastActive: nil,
            current: nil
        )?.source.bundleIdentifier
    }

    @Test func playingBrowserBeatsPausedSpotify() {
        let spotify = snapshot("com.spotify.client", playing: false)
        #expect(choose(scripted: [spotify], system: snapshot("com.google.Chrome", playing: true)) == "com.google.Chrome")
    }

    @Test func pausedSystemSessionBeatsPausedSpotify() {
        let spotify = snapshot("com.spotify.client", playing: false)
        #expect(choose(scripted: [spotify], system: snapshot("com.google.Chrome", playing: false)) == "com.google.Chrome")
    }

    @Test func playingSpotifyBeatsPausedBrowser() {
        let spotify = snapshot("com.spotify.client", playing: true)
        #expect(choose(scripted: [spotify], system: snapshot("com.google.Chrome", playing: false)) == "com.spotify.client")
    }

    @Test func scriptedTwinKeepsPlayerVolume() {
        let spotify = snapshot("com.spotify.client", playing: true, volume: 0.4)
        let system = snapshot("com.spotify.client", playing: true)
        let chosen = MediaPlayerNowPlayingService.choose(
            scripted: [spotify],
            system: system,
            preferred: nil,
            lastActive: nil,
            current: nil
        )
        #expect(chosen?.volume == 0.4)
    }

    @Test func manualPickWins() {
        let music = snapshot("com.apple.Music", playing: false)
        let system = snapshot("com.google.Chrome", playing: true)
        #expect(choose(scripted: [music], system: system, preferred: .music) == "com.apple.Music")
    }

    @Test func fallsBackToScriptedPlayersWithoutSystemSession() {
        let music = snapshot("com.apple.Music", playing: false)
        let spotify = snapshot("com.spotify.client", playing: true)
        #expect(choose(scripted: [music, spotify], system: nil) == "com.spotify.client")
        #expect(choose(scripted: [], system: nil) == nil)
    }
}

struct ToolboxMenuLayoutMigrationTests {
    @Test func movesExistingInstallsToPanelOnce() throws {
        let defaults = try #require(UserDefaults(suiteName: "menu-migration-\(UUID().uuidString)"))
        defaults.set(ToolboxMenuLayout.expanded.rawValue, forKey: ToolboxSettings.Keys.menuLayout)

        ToolboxSettings.registerDefaults(in: defaults)
        #expect(defaults.string(forKey: ToolboxSettings.Keys.menuLayout) == ToolboxMenuLayout.panel.rawValue)

        // A layout picked after the migration sticks.
        defaults.set(ToolboxMenuLayout.grouped.rawValue, forKey: ToolboxSettings.Keys.menuLayout)
        ToolboxSettings.registerDefaults(in: defaults)
        #expect(defaults.string(forKey: ToolboxSettings.Keys.menuLayout) == ToolboxMenuLayout.grouped.rawValue)
    }
}

extension DynamicIslandViewModelTests {
    @Test func pausedTrackStaysInTheClosedIslandOnlyAfterPlaying() {
        let viewModel = makeViewModel(settings: StubIslandSettings { $0.showsTrackChanges = false })

        // A session that was already paused (e.g. an old video tab) stays out.
        nowPlaying.emit(track("old", isPlaying: false))
        #expect(viewModel.mode == .idle)
        #expect(viewModel.nowPlaying != nil)

        // Pausing something that was playing keeps it around for a while.
        nowPlaying.emit(track("a"))
        #expect(viewModel.mode == .compactMedia)
        nowPlaying.emit(track("a", isPlaying: false))
        #expect(viewModel.mode == .compactMedia)
    }
}

@MainActor
struct IslandStopwatchTests {
    private let start = Date(timeIntervalSinceReferenceDate: 10_000)

    @Test func pausesResumesAndRecordsLapSplits() {
        let stopwatch = IslandStopwatchViewModel()
        stopwatch.toggle(at: start)
        #expect(stopwatch.elapsed(at: start.addingTimeInterval(5)) == 5)

        stopwatch.lap(at: start.addingTimeInterval(5))
        stopwatch.toggle(at: start.addingTimeInterval(8))
        #expect(stopwatch.isPaused)
        #expect(stopwatch.elapsed(at: start.addingTimeInterval(100)) == 8)

        // Resuming continues from 8 s; the pause doesn't count.
        stopwatch.toggle(at: start.addingTimeInterval(100))
        stopwatch.lap(at: start.addingTimeInterval(104))
        #expect(stopwatch.laps == [5, 7])

        stopwatch.reset()
        #expect(!stopwatch.isActive)
        #expect(stopwatch.laps.isEmpty)
    }

    @Test func formatsTenths() {
        #expect(IslandFormat.stopwatch(65.37) == "01:05.3")
        #expect(IslandFormat.stopwatch(3725.0) == "1:02:05.0")
    }
}

@MainActor
struct KeepAwakeTests {
    @Test func timedKeepAwakeReportsItsEndAndTurnsOff() throws {
        let controls = ControlsViewModel()
        controls.keepAwake(forMinutes: 30)
        #expect(controls.isKeepingAwake)
        let until = try #require(controls.keepAwakeUntil)
        #expect(abs(until.timeIntervalSinceNow - 30 * 60) < 5)

        // Switching to "until turned off" drops the end time.
        controls.keepAwake(forMinutes: nil)
        #expect(controls.isKeepingAwake)
        #expect(controls.keepAwakeUntil == nil)

        controls.stopKeepingAwake()
        #expect(!controls.isKeepingAwake)
    }
}

@MainActor
private final class FakeCalendar: CalendarEventProviding {
    var accessState = CalendarAccessState.granted
    var events: [IslandCalendarEvent] = []

    func upcomingEvents(limit: Int) -> [IslandCalendarEvent] {
        Array(events.prefix(limit))
    }
}

@MainActor
struct EventReminderTests {
    private let now = Date(timeIntervalSinceReferenceDate: 50_000)

    private func event(_ id: String, startsIn minutes: Double, allDay: Bool = false) -> IslandCalendarEvent {
        let start = now.addingTimeInterval(minutes * 60)
        return IslandCalendarEvent(
            id: id,
            title: id,
            start: start,
            end: start.addingTimeInterval(1800),
            isAllDay: allDay,
            color: .systemBlue
        )
    }

    @Test func remindsOnceShortlyBeforeTimedEvents() {
        let calendar = FakeCalendar()
        calendar.events = [
            event("soon", startsIn: 4),
            event("later", startsIn: 30),
            event("holiday", startsIn: 3, allDay: true),
            event("started", startsIn: -2)
        ]
        let monitor = EventReminderMonitor(calendar: calendar)

        #expect(monitor.takeDueEvents(at: now).map(\.id) == ["soon"])
        #expect(monitor.takeDueEvents(at: now.addingTimeInterval(60)).isEmpty)
    }

    @Test func staysQuietWithoutCalendarAccess() {
        let calendar = FakeCalendar()
        calendar.accessState = .notDetermined
        calendar.events = [event("soon", startsIn: 2)]

        #expect(EventReminderMonitor(calendar: calendar).takeDueEvents(at: now).isEmpty)
    }
}

struct MeetingLinkTests {
    @Test func findsKnownMeetingLinksInEventFields() {
        let zoom = MeetingLink.find(url: nil, location: "Zoom: https://us02web.zoom.us/j/123456789?pwd=abc", notes: nil)
        #expect(zoom?.service == .zoom)
        #expect(zoom?.url.absoluteString == "https://us02web.zoom.us/j/123456789?pwd=abc")

        let meet = MeetingLink.find(url: nil, location: nil, notes: "Agenda: https://docs.google.com/x\nJoin: https://meet.google.com/abc-defg-hij")
        #expect(meet?.service == .googleMeet)

        let teams = MeetingLink.find(
            url: URL(string: "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc"),
            location: nil,
            notes: nil
        )
        #expect(teams?.service == .teams)
    }

    @Test func ignoresOrdinaryLinks() {
        #expect(MeetingLink.find(url: URL(string: "https://zoom.us/pricing"), location: "Room 4", notes: "https://example.com") == nil)
        #expect(MeetingLink.find(url: nil, location: "https://meet.google.com/", notes: nil) == nil)
    }

    @Test func eventURLWinsOverNotes() {
        let link = MeetingLink.find(
            url: URL(string: "https://acme.webex.com/meet/jane"),
            location: nil,
            notes: "https://meet.google.com/abc-defg-hij"
        )
        #expect(link?.service == .webex)
    }

    @MainActor
    @Test func reminderBannerOffersJoinForMeetings() throws {
        let now = Date(timeIntervalSinceReferenceDate: 50_000)
        var event = IslandCalendarEvent(
            id: "standup",
            title: "Standup",
            start: now.addingTimeInterval(240),
            end: now.addingTimeInterval(1_800),
            isAllDay: false,
            color: .systemBlue
        )
        #expect(EventReminderMonitor.banner(for: event, now: now).action == nil)

        let url = try #require(URL(string: "https://meet.google.com/abc-defg-hij"))
        event.meetingLink = MeetingLink(url)
        let action = EventReminderMonitor.banner(for: event, now: now).action
        #expect(action?.url.absoluteString == "https://meet.google.com/abc-defg-hij")
    }
}
