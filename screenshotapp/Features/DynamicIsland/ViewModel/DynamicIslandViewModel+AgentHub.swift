import Foundation

/// The AI agents hub opens the island when an agent waits on the user.
extension DynamicIslandViewModel: AgentHubAttentionPresenting {
    var canShowAgentHub: Bool {
        isEnabled && preferences.visiblePanels.contains(.aiAgents)
    }

    func beginAgentAttention() {
        beginAttention(on: .aiAgents)
    }

    func endAgentAttention() {
        endAttention()
    }

    func announce(_ banner: DynamicIslandNotification, peek: String) {
        postAlert(banner, peek: peek)
    }
}
