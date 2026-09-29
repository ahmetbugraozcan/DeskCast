import Combine
import Foundation

/// Keeps the closed island's idle content fresh: the next calendar event and
/// Claude's 5-hour limit. Runs only while the island is on and its idle
/// content may show them, checks once a minute, and never asks for calendar
/// access itself (the Calendar panel does that).
@MainActor
final class IdleInfoMonitor {
    private struct Needs: Equatable {
        var event = false
        var claudeUsage = false
    }

    private let calendar: CalendarEventProviding
    private let usage: AIUsageService
    private weak var island: DynamicIslandViewModel?
    private var needs = Needs()
    private var timer: Timer?
    private var settingsObserver: AnyCancellable?
    private var usageTask: Task<Void, Never>?

    /// A meeting this close counts as "soon" for the automatic island.
    static let soonWindow: TimeInterval = 60 * 60
    /// Events further out than this aren't shown at all.
    static let lookahead: TimeInterval = 12 * 60 * 60
    private static let checkInterval: TimeInterval = 60

    init(calendar: CalendarEventProviding? = nil, usage: AIUsageService = AIUsageService()) {
        self.calendar = calendar ?? CalendarService()
        self.usage = usage
    }

    func bind(to island: DynamicIslandViewModel) {
        self.island = island
        settingsObserver = island.$isEnabled
            .combineLatest(island.$preferences)
            .map { isEnabled, preferences in
                let content = preferences.idleContent
                return Needs(
                    event: isEnabled && [.automatic, .nextEvent].contains(content),
                    claudeUsage: isEnabled && [.automatic, .claudeUsage].contains(content)
                )
            }
            .removeDuplicates()
            .sink { [weak self] needs in
                self?.apply(needs)
            }
    }

    private func apply(_ needs: Needs) {
        self.needs = needs
        timer?.invalidate()
        timer = nil

        if !needs.event {
            island?.updateIdleEvent(nil)
        }
        if !needs.claudeUsage {
            usageTask?.cancel()
            usageTask = nil
            island?.updateIdleClaudeUsage(nil)
        }

        guard needs.event || needs.claudeUsage else { return }

        check()
        let timer = Timer(timeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.check()
            }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func check() {
        if needs.event {
            island?.updateIdleEvent(Self.nextEvent(in: calendar.upcomingEvents(limit: 12), at: Date()))
        }

        if needs.claudeUsage, usageTask == nil {
            let usage = usage
            usageTask = Task { [weak self] in
                let fraction = await Task.detached(priority: .utility) { usage.claudeSessionUsage() }.value
                guard let self, !Task.isCancelled else { return }
                usageTask = nil
                if needs.claudeUsage {
                    island?.updateIdleClaudeUsage(fraction)
                }
            }
        }
    }

    /// The next timed event that hasn't started, within the lookahead.
    static func nextEvent(in events: [IslandCalendarEvent], at now: Date) -> IdleCalendarEvent? {
        guard let event = events
            .filter({ !$0.isAllDay && $0.start > now && $0.start.timeIntervalSince(now) <= lookahead })
            .min(by: { $0.start < $1.start }) else {
            return nil
        }
        return IdleCalendarEvent(event: event, isSoon: event.start.timeIntervalSince(now) <= soonWindow)
    }
}
