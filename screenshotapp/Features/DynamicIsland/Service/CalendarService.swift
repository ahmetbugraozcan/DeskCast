import AppKit
import EventKit

struct IslandCalendarEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: NSColor
}

enum CalendarAccessState: Equatable {
    case notDetermined
    case granted
    case denied
}

/// Upcoming events through EventKit (full read access, asked on first use).
@MainActor
final class CalendarService {
    private let store = EKEventStore()

    var accessState: CalendarAccessState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    /// Events from now until the end of tomorrow, in start order.
    func upcomingEvents(limit: Int = 6) -> [IslandCalendarEvent] {
        guard accessState == .granted else { return [] }

        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)

        guard let end = calendar.date(byAdding: .day, value: 2, to: startOfToday) else { return [] }

        let predicate = store.predicateForEvents(withStart: startOfToday, end: end, calendars: nil)

        return store.events(matching: predicate)
            .filter { $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
            .prefix(limit)
            .map { event in
                IslandCalendarEvent(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    title: event.title ?? "",
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay,
                    color: event.calendar?.color ?? .systemBlue
                )
            }
    }

    /// Days in the current week that have at least one event.
    func daysWithEvents(in week: [Date]) -> Set<Date> {
        guard accessState == .granted, let first = week.first, let last = week.last,
              let end = Calendar.current.date(byAdding: .day, value: 1, to: last)
        else {
            return []
        }

        let predicate = store.predicateForEvents(withStart: first, end: end, calendars: nil)
        let calendar = Calendar.current
        return Set(store.events(matching: predicate).map { calendar.startOfDay(for: $0.startDate) })
    }

    func openCalendarApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
