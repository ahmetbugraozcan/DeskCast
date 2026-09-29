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
        let banner = Self.banner(for: session, duration: duration)
        island.postAlert(banner, peek: banner.title)
    }

    static func banner(for session: AgentSession, duration: TimeInterval) -> DynamicIslandNotification {
        let minutes = max(Int((duration / 60).rounded()), 1)
        return DynamicIslandNotification(
            caption: session.project,
            title: AppLocalization.formatted("island.agents.finished", session.kind.displayName),
            message: AppLocalization.formatted("island.agents.minutes", minutes),
            systemImage: session.kind.systemImage,
            style: .success
        )
    }
}
