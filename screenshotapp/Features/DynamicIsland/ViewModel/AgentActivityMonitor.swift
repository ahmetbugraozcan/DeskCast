import Combine
import Foundation

/// Mirrors Claude Code and Codex turns in progress into the island, and
/// announces long turns when they finish.
@MainActor
final class AgentActivityMonitor {
    private let service: AgentActivityProviding
    private weak var island: DynamicIslandViewModel?
    private var settingsObserver: AnyCancellable?

    init(service: AgentActivityProviding? = nil) {
        self.service = service ?? AgentActivityService()
    }

    func bind(to island: DynamicIslandViewModel) {
        self.island = island
        service.onUpdate = { [weak self] sessions in
            self?.island?.updateAgentSessions(sessions)
        }
        service.onFinish = { [weak self] session, duration in
            self?.announce(session, duration: duration)
        }
        settingsObserver = island.$isEnabled
            .combineLatest(island.$preferences)
            .map { isEnabled, preferences in
                isEnabled && (preferences.showsAgentActivity || preferences.agentFinishAlerts)
            }
            .removeDuplicates()
            .sink { [weak self] active in
                self?.setActive(active)
            }
    }

    private func setActive(_ active: Bool) {
        if active {
            service.start()
        } else {
            service.stop()
            island?.updateAgentSessions([])
        }
    }

    private func announce(_ session: AgentSession, duration: TimeInterval) {
        guard let island, island.isEnabled, island.preferences.agentFinishAlerts,
              duration >= TimeInterval(island.preferences.agentFinishMinimumMinutes * 60) else {
            return
        }
        island.post(Self.banner(for: session, duration: duration, fullBanner: island.preferences.agentFinishFullBanner))
    }

    /// The full banner names the project and how long the turn took; the
    /// compact one only says who finished, in the closed island's wings.
    static func banner(for session: AgentSession, duration: TimeInterval, fullBanner: Bool) -> DynamicIslandNotification {
        let title = AppLocalization.formatted("island.agents.finished", session.kind.displayName)

        guard fullBanner else {
            var peek = DynamicIslandNotification(title: title, message: nil, systemImage: session.kind.systemImage, style: .success)
            peek.isCompact = true
            return peek
        }

        let minutes = max(Int((duration / 60).rounded()), 1)
        return DynamicIslandNotification(
            caption: session.project,
            title: title,
            message: AppLocalization.formatted("island.agents.minutes", minutes),
            systemImage: session.kind.systemImage,
            style: .success
        )
    }
}
