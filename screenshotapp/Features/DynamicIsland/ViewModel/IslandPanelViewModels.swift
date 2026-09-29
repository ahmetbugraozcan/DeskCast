import AppKit
import AVFoundation
import Combine
import CoreAudio

/// Panel view models poll only while their panel is on screen: each view calls
/// `setActive(true)` on appear and `setActive(false)` on disappear.
@MainActor
protocol IslandPanelActivating: AnyObject {
    func setActive(_ active: Bool)
}

// MARK: - System

@MainActor
final class SystemStatsViewModel: ObservableObject, IslandPanelActivating {
    @Published private(set) var stats = SystemStatsSnapshot()

    private let service: SystemStatsService
    private let queue = DispatchQueue(label: "com.ahmetbugraozcan.screenshotapp.systemstats", qos: .utility)
    private var timer: Timer?

    init(service: SystemStatsService = SystemStatsService()) {
        self.service = service
    }

    func setActive(_ active: Bool) {
        timer?.invalidate()
        timer = nil

        guard active else { return }

        sample()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sample()
            }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func sample() {
        let service = service

        queue.async { [weak self] in
            let snapshot = service.sample()

            Task { @MainActor in
                self?.stats = snapshot
            }
        }
    }
}

// MARK: - Audio

@MainActor
final class AudioViewModel: ObservableObject, IslandPanelActivating {
    @Published private(set) var volume: Double = 0
    @Published private(set) var isMuted = false
    @Published private(set) var hasVolumeControl = true
    @Published private(set) var devices: [AudioDevice] = []
    @Published private(set) var currentDeviceID: AudioDeviceID?
    @Published private(set) var inputVolume: Double?
    @Published private(set) var isMicrophoneMuted = false
    @Published private(set) var appSources: [AppAudioSource] = []
    @Published private(set) var appVolumes: [String: Double] = [:]

    private let service: AudioOutputService
    private let appVolume: AppVolumeService
    private var timer: Timer?
    /// Keeps adjusted apps' taps current (new helper processes, quit apps,
    /// output changes) while the panel is closed.
    private var tapMaintenanceTimer: Timer?
    private var tick = 0
    private var activeCount = 0
    /// Input level to restore when the microphone is un-muted by volume.
    private var savedInputVolume: Double?

    init(service: AudioOutputService? = nil, appVolume: AppVolumeService? = nil) {
        self.service = service ?? AudioOutputService()
        self.appVolume = appVolume ?? AppVolumeService()
    }

    var currentDeviceName: String {
        devices.first { $0.id == currentDeviceID }?.name ?? AppLocalization.string("island.audio.output")
    }

    /// Several panels (Now Playing, Volume, Controls) share this model.
    func setActive(_ active: Bool) {
        activeCount = max(activeCount + (active ? 1 : -1), 0)

        if activeCount > 0, timer == nil {
            refresh()
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refresh()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else if activeCount == 0 {
            timer?.invalidate()
            timer = nil
        }
    }

    func refresh() {
        let currentVolume = service.volume()
        hasVolumeControl = currentVolume != nil
        setIfChanged(\.volume, currentVolume ?? 0)
        setIfChanged(\.isMuted, service.isMuted())
        setIfChanged(\.currentDeviceID, service.defaultDevice())
        setIfChanged(\.devices, service.outputDevices())

        let input = service.volume(input: true)
        setIfChanged(\.inputVolume, input)
        setIfChanged(\.isMicrophoneMuted, service.isMuted(input: true) || input == 0)

        // Listing audio processes is heavier; once a second is plenty.
        tick += 1
        if tick % 2 == 1 {
            refreshAppSources()
        }
    }

    // MARK: - Per-app volume

    func volume(for source: AppAudioSource) -> Double {
        appVolumes[source.id] ?? 1
    }

    func setVolume(_ value: Double, for source: AppAudioSource) {
        appVolume.setVolume(value, for: source)
        appVolumes[source.id] = value >= 0.995 ? nil : value
        updateTapMaintenance()
    }

    func toggleMute(_ source: AppAudioSource) {
        setVolume(volume(for: source) > 0 ? 0 : 1, for: source)
    }

    private func refreshAppSources() {
        let sources = appVolume.audioSources()
        let outputUID = service.defaultDevice().flatMap(service.deviceUID)
        appVolume.sync(sources: sources, outputUID: outputUID)
        setIfChanged(\.appSources, sources)

        let volumes = Dictionary(uniqueKeysWithValues: sources.compactMap { source -> (String, Double)? in
            let value = appVolume.volume(for: source.id)
            return value < 0.995 ? (source.id, value) : nil
        })
        setIfChanged(\.appVolumes, volumes)
        updateTapMaintenance()
    }

    private func updateTapMaintenance() {
        if appVolumes.isEmpty {
            tapMaintenanceTimer?.invalidate()
            tapMaintenanceTimer = nil
        } else if tapMaintenanceTimer == nil {
            let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.activeCount == 0 else { return }
                    self.refreshAppSources()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            tapMaintenanceTimer = timer
        }
    }

    func setVolume(_ value: Double) {
        volume = value
        service.setVolume(value)

        if value > 0 {
            isMuted = false
        }
    }

    func setInputVolume(_ value: Double) {
        inputVolume = value
        isMicrophoneMuted = value == 0
        service.setVolume(value, input: true)

        if value > 0 {
            service.setMuted(false, input: true)
        }
    }

    func toggleMute() {
        let newValue = !isMuted

        if service.setMuted(newValue) {
            isMuted = newValue
        }
    }

    func selectDevice(_ id: AudioDeviceID) {
        service.setDefaultOutputDevice(id)
        refresh()
    }

    func toggleMicrophone() {
        if isMicrophoneMuted {
            if !service.setMuted(false, input: true) || (inputVolume ?? 0) == 0 {
                service.setVolume(savedInputVolume ?? 0.75, input: true)
            }
        } else if !service.setMuted(true, input: true) {
            // Many built-in mics have no mute switch; drop the input level instead.
            savedInputVolume = inputVolume
            service.setVolume(0, input: true)
        }

        refresh()
    }

    private func setIfChanged<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<AudioViewModel, Value>, _ value: Value) {
        if self[keyPath: keyPath] != value {
            self[keyPath: keyPath] = value
        }
    }
}

// MARK: - AI agents

@MainActor
final class AIUsageViewModel: ObservableObject, IslandPanelActivating {
    enum SpendPeriod: String, CaseIterable, Identifiable {
        case today
        case week

        var id: String { rawValue }
    }

    @Published private(set) var report = AIUsageReport()
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false
    /// The spend scan finished at least once (limits arrive first).
    @Published private(set) var hasLoadedSpend = false
    @Published var spendPeriod: SpendPeriod = .today

    private let service: AIUsageService
    private var timer: Timer?
    private var loadTask: Task<Void, Never>?

    private static let refreshInterval: TimeInterval = 90

    init(service: AIUsageService = AIUsageService()) {
        self.service = service
    }

    var spend: AIDailySpend {
        let days = spendPeriod == .today ? Array(report.dailySpend.suffix(1)) : report.dailySpend

        return days.reduce(AIDailySpend(day: Date(), cost: 0, tokens: 0, cacheReadTokens: 0)) { total, day in
            AIDailySpend(
                day: total.day,
                cost: total.cost + day.cost,
                tokens: total.tokens + day.tokens,
                cacheReadTokens: total.cacheReadTokens + day.cacheReadTokens
            )
        }
    }

    func setActive(_ active: Bool) {
        timer?.invalidate()
        timer = nil

        guard active else { return }

        refresh()
        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Limits first (small files), then spend (transcripts, read
    /// incrementally), each published as soon as it's ready.
    func refresh() {
        guard loadTask == nil else { return }

        isLoading = true
        let service = service

        loadTask = Task { [weak self] in
            let limits = await Task.detached(priority: .userInitiated) {
                await service.loadLimits()
            }.value
            self?.applyLimits(limits)

            let spend = await Task.detached(priority: .utility) {
                service.loadSpend()
            }.value

            guard let self else { return }
            report.dailySpend = spend
            isLoading = false
            hasLoadedSpend = true
            loadTask = nil
        }
    }

    /// Reads transcripts in the background shortly after launch, so the
    /// first look at the panel doesn't wait for a cold scan.
    func warmUp(after delay: Duration = .seconds(8), when shouldLoad: @escaping () -> Bool) {
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard shouldLoad() else { return }
            self?.refresh()
        }
    }

    private func applyLimits(_ limits: AIUsageReport) {
        report.claude = limits.claude
        report.codex = limits.codex
        hasLoaded = true
    }
}

// MARK: - Calendar

@MainActor
final class CalendarViewModel: ObservableObject, IslandPanelActivating {
    @Published private(set) var accessState: CalendarAccessState
    @Published private(set) var events: [IslandCalendarEvent] = []
    @Published private(set) var week: [Date] = []
    @Published private(set) var daysWithEvents: Set<Date> = []

    private let service: CalendarService

    init(service: CalendarService? = nil) {
        let service = service ?? CalendarService()
        self.service = service
        accessState = service.accessState
    }

    func setActive(_ active: Bool) {
        guard active else { return }
        reload()
    }

    func requestAccess() {
        Task {
            _ = await service.requestAccess()
            reload()
        }
    }

    func openCalendar() {
        service.openCalendarApp()
    }

    private func reload() {
        accessState = service.accessState

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let offset = (weekday - calendar.firstWeekday + 7) % 7

        if let weekStart = calendar.date(byAdding: .day, value: -offset, to: today) {
            week = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
        }

        events = service.upcomingEvents()
        daysWithEvents = service.daysWithEvents(in: week)
    }
}

// MARK: - Downloads

@MainActor
final class DownloadsViewModel: ObservableObject, IslandPanelActivating {
    @Published private(set) var files: [DownloadedFile] = []

    private let service = DownloadsService()
    private var timer: Timer?

    func setActive(_ active: Bool) {
        timer?.invalidate()
        timer = nil

        guard active else { return }

        reload()
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reload()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func open(_ file: DownloadedFile) {
        NSWorkspace.shared.open(file.url)
    }

    func reveal(_ file: DownloadedFile) {
        NSWorkspace.shared.activateFileViewerSelecting([file.url])
    }

    func openFolder() {
        NSWorkspace.shared.open(service.folderURL)
    }

    private func reload() {
        let service = service

        Task { [weak self] in
            let files = await Task.detached(priority: .utility) {
                service.recentFiles()
            }.value

            if self?.files != files {
                self?.files = files
            }
        }
    }
}

// MARK: - Timer

@MainActor
final class IslandTimerViewModel: ObservableObject {
    /// Which page the Timer panel shows; the stopwatch runs independently.
    @Published var panelMode = IslandTimerPanelMode.timer
    @Published private(set) var totalDuration: TimeInterval = 5 * 60
    @Published private(set) var endDate: Date?
    @Published private(set) var pausedRemaining: TimeInterval?

    /// Called when a running timer reaches zero.
    var onFinish: (() -> Void)?

    private var finishTask: Task<Void, Never>?

    static let presetMinutes = [1, 5, 10, 25, 45]

    var isRunning: Bool { endDate != nil }
    var isPaused: Bool { pausedRemaining != nil }
    var isActive: Bool { isRunning || isPaused }

    func remaining(at date: Date = Date()) -> TimeInterval {
        if let endDate {
            return max(endDate.timeIntervalSince(date), 0)
        }

        return pausedRemaining ?? totalDuration
    }

    func progress(at date: Date = Date()) -> Double {
        guard totalDuration > 0 else { return 0 }
        return min(max(remaining(at: date) / totalDuration, 0), 1)
    }

    func start(minutes: Int) {
        totalDuration = TimeInterval(minutes * 60)
        pausedRemaining = nil
        run(for: totalDuration)
    }

    func toggle() {
        if isRunning {
            pausedRemaining = remaining()
            endDate = nil
            finishTask?.cancel()
        } else {
            run(for: pausedRemaining ?? totalDuration)
            pausedRemaining = nil
        }
    }

    func addMinute() {
        if let endDate {
            self.endDate = endDate.addingTimeInterval(60)
            totalDuration += 60
            scheduleFinish()
        } else if let pausedRemaining {
            self.pausedRemaining = pausedRemaining + 60
            totalDuration += 60
        } else {
            totalDuration += 60
        }
    }

    func reset() {
        finishTask?.cancel()
        endDate = nil
        pausedRemaining = nil
    }

    private func run(for duration: TimeInterval) {
        guard duration > 0 else { return }
        endDate = Date().addingTimeInterval(duration)
        scheduleFinish()
    }

    private func scheduleFinish() {
        finishTask?.cancel()

        guard let endDate else { return }

        finishTask = Task { [weak self] in
            let delay = max(endDate.timeIntervalSinceNow, 0)
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, self.endDate == endDate else { return }
            self.endDate = nil
            NSSound(named: NSSound.Name("Glass"))?.play()
            self.onFinish?()
        }
    }
}

enum IslandTimerPanelMode: String, CaseIterable, Identifiable {
    case timer
    case stopwatch

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .timer: "island.panel.timer"
        case .stopwatch: "island.stopwatch.title"
        }
    }
}

// MARK: - Stopwatch

@MainActor
final class IslandStopwatchViewModel: ObservableObject {
    /// Set while running: when the stopwatch would have started had it never paused.
    @Published private(set) var startDate: Date?
    /// Set while paused.
    @Published private(set) var pausedElapsed: TimeInterval?
    /// Split times (time since the previous lap), oldest first.
    @Published private(set) var laps: [TimeInterval] = []

    private var lastLapElapsed: TimeInterval = 0

    var isRunning: Bool { startDate != nil }
    var isPaused: Bool { pausedElapsed != nil }
    var isActive: Bool { isRunning || isPaused }

    func elapsed(at date: Date = Date()) -> TimeInterval {
        if let startDate {
            return max(date.timeIntervalSince(startDate), 0)
        }
        return pausedElapsed ?? 0
    }

    func toggle(at date: Date = Date()) {
        if isRunning {
            pausedElapsed = elapsed(at: date)
            startDate = nil
        } else {
            startDate = date.addingTimeInterval(-(pausedElapsed ?? 0))
            pausedElapsed = nil
        }
    }

    func lap(at date: Date = Date()) {
        guard isRunning else { return }
        let total = elapsed(at: date)
        laps.append(total - lastLapElapsed)
        lastLapElapsed = total
    }

    func reset() {
        startDate = nil
        pausedElapsed = nil
        laps = []
        lastLapElapsed = 0
    }
}

// MARK: - Controls

@MainActor
final class ControlsViewModel: ObservableObject, IslandPanelActivating {
    @Published private(set) var isDarkMode = false
    @Published private(set) var isKeepingAwake = false
    /// End of a timed keep-awake; `nil` while off or on until turned off.
    @Published private(set) var keepAwakeUntil: Date?

    static let keepAwakeMinuteOptions = [30, 60, 120]

    private let service: SystemControlsService
    private var keepAwakeTask: Task<Void, Never>?

    init(service: SystemControlsService? = nil) {
        let service = service ?? SystemControlsService()
        self.service = service
        isDarkMode = service.isDarkMode
    }

    func setActive(_ active: Bool) {
        guard active else { return }
        isDarkMode = service.isDarkMode
        isKeepingAwake = service.isKeepingAwake
    }

    func toggleDarkMode() {
        // Optimistic; re-read once System Events has applied it.
        isDarkMode.toggle()
        service.toggleDarkMode { [weak self] in
            guard let self else { return }
            self.isDarkMode = self.service.isDarkMode
        }
    }

    func toggleKeepAwake() {
        if service.isKeepingAwake {
            stopKeepingAwake()
        } else {
            keepAwake(forMinutes: nil)
        }
    }

    /// Keeps the display awake for a while (`nil` = until turned off).
    func keepAwake(forMinutes minutes: Int?) {
        keepAwakeTask?.cancel()
        keepAwakeTask = nil
        service.setKeepAwake(true)
        isKeepingAwake = service.isKeepingAwake

        guard isKeepingAwake, let minutes else {
            keepAwakeUntil = nil
            return
        }

        let until = Date().addingTimeInterval(TimeInterval(minutes * 60))
        keepAwakeUntil = until
        keepAwakeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(until.timeIntervalSinceNow))
            guard !Task.isCancelled else { return }
            self?.stopKeepingAwake()
        }
    }

    func stopKeepingAwake() {
        keepAwakeTask?.cancel()
        keepAwakeTask = nil
        keepAwakeUntil = nil
        service.setKeepAwake(false)
        isKeepingAwake = service.isKeepingAwake
    }

    func sleepDisplay() {
        service.sleepDisplay()
    }

    func startScreenSaver() {
        service.startScreenSaver()
    }

    func openSystemSettings() {
        service.openSystemSettings()
    }
}

// MARK: - Camera

@MainActor
final class CameraMirrorViewModel: ObservableObject, IslandPanelActivating {
    @Published private(set) var authorization: AVAuthorizationStatus = CameraPreviewService.authorizationStatus

    let preview = CameraPreviewService()

    func setActive(_ active: Bool) {
        authorization = CameraPreviewService.authorizationStatus

        if active, authorization == .authorized {
            preview.start()
        } else {
            preview.stop()
        }
    }

    func requestAccess() {
        Task {
            _ = await CameraPreviewService.requestAccess()
            setActive(true)
        }
    }
}

// MARK: - Container

/// DeskCast actions the Tools / Captures / Files panels trigger. Supplied by the
/// composition root so the island doesn't depend on other features' types.
struct IslandToolActions {
    var captureArea: () -> Void = {}
    var captureVideo: () -> Void = {}
    var captureText: () -> Void = {}
    var copyFinderPath: () -> Void = {}
    var toggleDropShelf: () -> Void = {}
    var openSettings: () -> Void = {}
}

/// Everything the expanded panels render, built once in `AppEnvironment`.
@MainActor
final class IslandPanelModels {
    let system = SystemStatsViewModel()
    let audio = AudioViewModel()
    let aiUsage = AIUsageViewModel()
    let calendar = CalendarViewModel()
    let downloads = DownloadsViewModel()
    let devices = DevicesViewModel()
    let weather = WeatherViewModel()
    let focus = FocusIndicatorMonitor()
    let agents = AgentActivityMonitor()
    let timer: IslandTimerViewModel
    let controls = ControlsViewModel()
    let camera = CameraMirrorViewModel()
    let clipboard = ClipboardHistoryViewModel()
    let stopwatch = IslandStopwatchViewModel()
    let eventReminders = EventReminderMonitor()
    let extras = NowPlayingExtrasViewModel()
    let screenshots: ScreenshotShelfViewModel
    let dropShelf: DropShelfViewModel
    let actions: IslandToolActions

    init(
        timer: IslandTimerViewModel,
        screenshots: ScreenshotShelfViewModel,
        dropShelf: DropShelfViewModel,
        actions: IslandToolActions
    ) {
        self.timer = timer
        self.screenshots = screenshots
        self.dropShelf = dropShelf
        self.actions = actions
    }

    /// Background features that follow the island's on/off state and settings.
    func bind(to island: DynamicIslandViewModel) {
        clipboard.bind(to: island)
        aiUsage.warmUp { [weak island] in
            island?.isEnabled == true && island?.preferences.visiblePanels.contains(.aiAgents) == true
        }
        eventReminders.bind(to: island)
        weather.bind(to: island)
        focus.bind(to: island)
        agents.bind(to: island)
    }
}
