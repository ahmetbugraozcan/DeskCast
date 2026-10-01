import SwiftUI

extension AgentKind {
    var tint: Color {
        switch self {
        case .claude: IslandPalette.claude
        case .codex: IslandPalette.codex
        }
    }
}

// MARK: - Compact agent

/// Closed island while Claude Code or Codex works: the agents on the left,
/// how long the oldest turn has run (or a running timer) on the right.
struct CompactAgentView: View {
    let sessions: [AgentSession]
    @ObservedObject var timer: IslandTimerViewModel
    let showsTimer: Bool
    var showsFocus = false
    let geometry: DynamicIslandGeometry

    @AppStorage(AgentHubSettings.Keys.showsMascot) private var showsMascot = AgentHubSettings.defaultShowsMascot

    var body: some View {
        let height = geometry.notchSize.height
        let kinds = AgentKind.allCases.filter { kind in sessions.contains { $0.kind == kind } }
        let tint = kinds.first?.tint ?? IslandPalette.claude

        HStack(spacing: 8) {
            if showsMascot {
                BipMascotView(mood: .working, size: height + 2, isInteractive: false)
                    .frame(width: height - 8, height: height)
            } else {
                agentIcons(kinds, height: height)
            }

            // Without a hardware notch the middle is visible, so name the project.
            if geometry.hasNotch {
                Spacer(minLength: geometry.notchSize.width)
            } else {
                Text(sessions.last?.project ?? kinds.map(\.displayName).joined(separator: " + "))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }

            if showsFocus {
                IslandFocusMoon()
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                if showsTimer {
                    Text(IslandFormat.clock(timer.remaining(at: context.date)))
                        .foregroundStyle(timer.isPaused ? .white.opacity(0.5) : .orange)
                } else {
                    Text(IslandFormat.clock(context.date.timeIntervalSince(sessions.first?.startedAt ?? context.date)))
                        .foregroundStyle(tint)
                }
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
        }
        .padding(.horizontal, 10)
        .frame(height: height)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(AppLocalization.formatted("island.agents.working", kinds.map(\.displayName).joined(separator: ", "))))
    }

    private func agentIcons(_ kinds: [AgentKind], height: CGFloat) -> some View {
        HStack(spacing: -3) {
            ForEach(kinds, id: \.self) { kind in
                Image(systemName: kind.systemImage)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(kind.tint)
                    .symbolEffect(.pulse, options: .repeating)
            }
        }
        .frame(minWidth: height - 12)
    }
}

// MARK: - Activity picker

/// One chip under the island: an activity, or "automatic" (shows them
/// together when a timer runs).
enum IslandActivityChip: Hashable, CaseIterable {
    case activity(IslandActivity)
    case automatic

    static var allCases: [IslandActivityChip] {
        IslandActivity.allCases.map(IslandActivityChip.activity) + [.automatic]
    }

    var choice: IslandActivity? {
        if case .activity(let activity) = self { activity } else { nil }
    }
}

struct IslandActivityChipButton: View {
    let chip: IslandActivityChip
    @ObservedObject var store: DynamicIslandViewModel

    var body: some View {
        let isSelected = store.activityChoice == chip.choice

        Button {
            store.chooseActivity(chip.choice)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isSelected ? Color.black : tint)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? Color.black : Color.white.opacity(0.9))
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Capsule().fill(isSelected ? Color.white : Color.black))
            .overlay(Capsule().stroke(.white.opacity(0.1), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }

    private var title: String {
        switch chip {
        case .activity(.media):
            store.nowPlaying?.source.displayName ?? AppLocalization.string("island.activity.music")
        case .activity(.agent):
            AgentKind.allCases.filter { kind in store.agentSessions.contains { $0.kind == kind } }
                .map(\.displayName).joined(separator: " + ")
        case .activity(.timer):
            AppLocalization.string("island.panel.timer")
        case .automatic:
            AppLocalization.string(store.timer.isActive ? "island.activity.together" : "island.activity.automatic")
        }
    }

    private var systemImage: String {
        switch chip {
        case .activity(.media): "music.note"
        case .activity(.agent): store.agentSessions.first?.kind.systemImage ?? "asterisk"
        case .activity(.timer): "timer"
        case .automatic: "square.stack.fill"
        }
    }

    private var tint: Color {
        switch chip {
        case .activity(.media): store.nowPlaying?.tintColor ?? IslandPalette.accent
        case .activity(.agent): store.agentSessions.first?.kind.tint ?? IslandPalette.claude
        case .activity(.timer): .orange
        case .automatic: .white
        }
    }
}
