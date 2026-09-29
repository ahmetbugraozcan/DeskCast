import SwiftUI

/// Closed-island next event: a calendar symbol in the event's color on the
/// left, the countdown (within the hour) or start time on the right. Displays
/// without a notch have room for the title too.
struct CompactEventView: View {
    let idle: IdleCalendarEvent
    var showsFocus = false
    let geometry: DynamicIslandGeometry

    var body: some View {
        let height = geometry.notchSize.height
        let event = idle.event

        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(nsColor: event.color))
                    .frame(width: height - 12)

                if showsFocus {
                    IslandFocusMoon()
                }

                if !geometry.hasNotch {
                    Text(event.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: geometry.hasNotch ? geometry.notchSize.width : 12)

                Text(Self.when(event.start, now: context.date))
                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(idle.isSoon ? Color(nsColor: event.color) : .white)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 10)
            .frame(height: height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(event.title), \(Self.when(event.start, now: Date()))"))
    }

    /// "25 min" within the hour, otherwise the start time ("14:30").
    static func when(_ start: Date, now: Date) -> String {
        let seconds = start.timeIntervalSince(now)
        guard seconds <= IdleInfoMonitor.soonWindow else {
            return start.formatted(date: .omitted, time: .shortened)
        }
        let minutes = max(Int((seconds / 60).rounded(.up)), 0)
        return AppLocalization.formatted("island.idle.inMinutes", minutes)
    }
}

/// Closed-island Claude limit: the Claude mark on the left, a ring and the
/// 5-hour share used on the right, orange then red as it runs out.
struct CompactClaudeView: View {
    let usedFraction: Double
    var showsFocus = false
    let geometry: DynamicIslandGeometry

    static let claudeOrange = Color(red: 0.85, green: 0.47, blue: 0.34)

    var body: some View {
        let height = geometry.notchSize.height
        let percent = Int((usedFraction * 100).rounded())
        let tint: Color = usedFraction >= 0.9 ? .red : Self.claudeOrange

        HStack(spacing: 8) {
            Image(systemName: "asterisk")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Self.claudeOrange)
                .frame(width: height - 12)

            if showsFocus {
                IslandFocusMoon()
            }

            Spacer(minLength: geometry.hasNotch ? geometry.notchSize.width : 12)

            HStack(spacing: 5) {
                ZStack {
                    Circle().stroke(tint.opacity(0.25), lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: usedFraction)
                        .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 12, height: 12)

                Text("\(percent)%")
                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(usedFraction >= Self.alertFraction ? tint : .white)
                    .contentTransition(.numericText(value: Double(percent)))
                    .animation(.snappy, value: percent)
            }
            .fixedSize()
        }
        .padding(.horizontal, 10)
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(AppLocalization.formatted("island.idle.claudeUsage", percent)))
    }

    private static var alertFraction: Double { DynamicIslandViewModel.claudeUsageAlertFraction }
}
