import SwiftUI

/// The island's AI agents panel: live Claude Code sessions (with
/// permission requests and questions), asking Claude, plan usage, and
/// integrations, one page at a time.
struct AgentHubPanelView: View {
    @ObservedObject var hub: AgentHubViewModel
    let usage: AIUsageViewModel

    var body: some View {
        ZStack {
            switch hub.tab {
            case .sessions:
                AgentSessionsView(hub: hub)
            case .usage:
                AIAgentsPanelView(model: usage)
            case .ask, .integrations:
                EmptyView()
            }
        }
        .transition(.opacity)
        .animation(.easeOut(duration: 0.2), value: hub.tab)
    }
}
