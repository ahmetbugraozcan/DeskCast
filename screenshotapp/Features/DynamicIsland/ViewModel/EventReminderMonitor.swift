import AppKit
import Combine

/// Upcoming calendar events, as read by `CalendarService`.
@MainActor
protocol CalendarEventProviding: AnyObject {
    var accessState: CalendarAccessState { get }
    func upcomingEvents(limit: Int) -> [IslandCalendarEvent]
}

extension CalendarService: CalendarEventProviding {}

/// Posts an island banner shortly before timed calendar events. Runs only
/// while the island and its "event reminders" setting are on, and never asks
/// for calendar access itself (the Calendar panel does that).
@MainActor
final class EventReminderMonitor {
    private let calendar: CalendarEventProviding
    private weak var island: DynamicIslandViewModel?
    private var timer: Timer?
    private var settingsObserver: AnyCancellable?
    /// Reminded occurrences (event id + start), so each fires once.
    private var reminded: [String: Date] = [:]

    static let leadTime: TimeInterval = 5 * 60
    private static let checkInterval: TimeInterval = 30

    init(calendar: CalendarEventProviding? = nil) {
        self.calendar = calendar ?? CalendarService()
    }

    func bind(to island: DynamicIslandViewModel) {
        self.island = island
        settingsObserver = island.$isEnabled
            .combineLatest(island.$preferences)
            .map { isEnabled, preferences in isEnabled && preferences.showsEventReminders }
            .removeDuplicates()
            .sink { [weak self] shouldRun in
                self?.setRunning(shouldRun)
            }
    }

    func setRunning(_ running: Bool) {
        timer?.invalidate()
        timer = nil

        guard running else { return }

        check()
        let timer = Timer(timeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.check()
            }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Timed events starting within the lead time that haven't been announced.
    /// Marks them as announced.
    func takeDueEvents(at now: Date = Date()) -> [IslandCalendarEvent] {
        guard calendar.accessState == .granted else { return [] }

        reminded = reminded.filter { $0.value > now.addingTimeInterval(-3600) }

        let due = calendar.upcomingEvents(limit: 12).filter { event in
            !event.isAllDay
                && event.start > now
                && event.start.timeIntervalSince(now) <= Self.leadTime
                && reminded[Self.key(for: event)] == nil
        }

        for event in due {
            reminded[Self.key(for: event)] = event.start
        }

        return due
    }

    private func check() {
        let now = Date()

        for event in takeDueEvents(at: now) {
            island?.post(Self.banner(for: event, now: now))
        }
    }

    private static func key(for event: IslandCalendarEvent) -> String {
        "\(event.id)|\(event.start.timeIntervalSinceReferenceDate)"
    }

    private static func banner(for event: IslandCalendarEvent, now: Date) -> DynamicIslandNotification {
        let minutes = max(Int((event.start.timeIntervalSince(now) / 60).rounded(.up)), 1)
        var banner = DynamicIslandNotification(
            caption: AppLocalization.string("island.panel.calendar"),
            title: event.title.isEmpty ? AppLocalization.string("island.panel.calendar") : event.title,
            message: AppLocalization.formatted(
                "island.calendar.startsIn",
                minutes,
                event.start.formatted(date: .omitted, time: .shortened)
            ),
            systemImage: "calendar",
            style: .info
        )
        banner.sourceAppURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal")
        return banner
    }
}
