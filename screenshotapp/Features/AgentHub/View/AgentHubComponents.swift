import SwiftUI

extension BipMood {
    var color: Color {
        let rgb = tint
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

extension AgentHubPhase {
    var color: Color { BipMood(phase: self).color }

    var titleKey: String { "agentHub.phase.\(rawValue)" }
}

extension AgentHubStep {
    /// "Editing · Invoice.swift", "Running · npm test", the prompt…
    var text: String {
        switch kind {
        case .prompt:
            return detail ?? AppLocalization.string("agentHub.step.prompt")
        case .tool(let tool):
            let label = Self.label(for: tool)
            return detail.map { "\(label) · \($0)" } ?? label
        case .failed(let tool):
            return AppLocalization.formatted("agentHub.step.failed", Self.label(for: tool))
        case .subagentStarted:
            return AppLocalization.string("agentHub.step.subagentStarted")
        case .subagentFinished:
            return AppLocalization.string("agentHub.step.subagentFinished")
        }
    }

    var systemImage: String {
        switch kind {
        case .prompt: "text.bubble"
        case .failed: "exclamationmark.triangle"
        case .subagentStarted, .subagentFinished: "person.2"
        case .tool(let tool): Self.symbol(for: tool)
        }
    }

    private static let toolKeys: [String: String] = [
        "Bash": "bash", "Read": "read", "Write": "write", "Edit": "edit", "MultiEdit": "edit",
        "Glob": "search", "Grep": "search", "LS": "list", "WebSearch": "webSearch", "WebFetch": "webFetch",
        "Task": "agent", "Agent": "agent", "TodoWrite": "todo", "NotebookEdit": "notebook"
    ]

    static func label(for tool: String) -> String {
        if let key = toolKeys[tool] {
            return AppLocalization.string("agentHub.tool.\(key)")
        }
        // MCP tools are "mcp__server__tool"; the tool name says the most.
        return tool.components(separatedBy: "__").last ?? tool
    }

    private static func symbol(for tool: String) -> String {
        switch tool {
        case "Bash": "terminal"
        case "Read": "doc.text"
        case "Write", "Edit", "MultiEdit", "NotebookEdit": "pencil"
        case "Glob", "Grep", "LS": "magnifyingglass"
        case "WebSearch", "WebFetch": "globe"
        case "Task", "Agent": "person.2"
        case "TodoWrite": "checklist"
        default: "wrench.and.screwdriver"
        }
    }
}

/// Text with a light sweeping across it, for the step that's running now.
struct AgentShimmerText: View {
    let text: String
    var size: CGFloat = 13

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.2) / 2.2
            Text(text)
                .font(.system(size: size, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.55), location: 0),
                            .init(color: .white.opacity(0.55), location: max(phase - 0.2, 0)),
                            .init(color: .white, location: phase),
                            .init(color: .white.opacity(0.55), location: min(phase + 0.2, 1)),
                            .init(color: .white.opacity(0.55), location: 1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
    }
}

/// A card with a soft glow of the state's color rising from its bottom.
struct AgentWashCard<Content: View>: View {
    var tint: Color?
    var padding: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                ZStack {
                    IslandPalette.card
                    if let tint {
                        RadialGradient(
                            colors: [tint.opacity(0.32), tint.opacity(0)],
                            center: UnitPoint(x: 0.5, y: 1.3),
                            startRadius: 0,
                            endRadius: 260
                        )
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(IslandPalette.cardStroke, lineWidth: 1)
            )
            .animation(.easeOut(duration: 0.3), value: tint == nil)
    }
}

/// Pill action button; the primary one is white.
struct AgentActionButton: View {
    let title: String
    var systemImage: String?
    var isPrimary = false
    var tint: Color?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 10.5, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isPrimary ? Color.black : (tint ?? .white))
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(
                Capsule().fill(isPrimary ? Color(white: 0.96) : Color.white.opacity(isHovered ? 0.15 : 0.09))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(IslandScaleButtonStyle())
        .onHover { isHovered = $0 }
        .fixedSize()
    }
}

/// Picks the panel's page; shown in the panel header.
struct AgentHubTabPicker: View {
    @ObservedObject var hub: AgentHubViewModel

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AgentHubTab.visibleCases) { tab in
                IslandChipButton(
                    title: AppLocalization.string(tab.titleKey),
                    isOn: hub.tab == tab
                ) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        hub.tab = tab
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if tab == .sessions, hub.attentionSession != nil, hub.tab != .sessions {
                        Circle().fill(Color.orange).frame(width: 7, height: 7).offset(x: 1, y: -1)
                    }
                }
            }
        }
    }
}
