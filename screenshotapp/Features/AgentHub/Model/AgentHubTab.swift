import Foundation

/// The pages of the island's AI agents panel.
nonisolated enum AgentHubTab: String, CaseIterable, Identifiable, Sendable {
    case sessions
    case ask
    case usage
    case integrations

    var id: String { rawValue }

    /// Pages that are built so far, in picker order.
    static let visibleCases: [AgentHubTab] = [.sessions, .usage]

    var titleKey: String {
        "agentHub.tab.\(rawValue)"
    }

    var systemImage: String {
        switch self {
        case .sessions: "terminal"
        case .ask: "bubble.left.and.text.bubble.right"
        case .usage: "gauge.with.dots.needle.33percent"
        case .integrations: "point.3.connected.trianglepath.dotted"
        }
    }
}
