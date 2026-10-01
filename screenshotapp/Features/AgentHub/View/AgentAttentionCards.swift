import SwiftUI

/// "Claude Code wants to run a command": the command, and Deny / Always
/// allow / Allow. Claude Code waits for the answer.
struct AgentApprovalCard: View {
    @ObservedObject var hub: AgentHubViewModel
    let request: AgentApprovalRequest
    let session: AgentHubSession?

    var body: some View {
        AgentWashCard(tint: AgentHubPhase.approval.color) {
            HStack(alignment: .top, spacing: 12) {
                BipMascotView(mood: .approval, size: 60)
                    .frame(maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(session?.title ?? "Claude Code")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AgentHubPhase.approval.color)
                            .lineLimit(1)
                        if hub.approvals.count > 1 {
                            Text("1/\(hub.approvals.count)")
                                .font(.system(size: 10, weight: .bold).monospacedDigit())
                                .foregroundStyle(.black)
                                .padding(.horizontal, 6)
                                .background(Capsule().fill(AgentHubPhase.approval.color))
                        }
                    }

                    Text(AppLocalization.formatted("agentHub.approval.title", toolName))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if let detail = request.detail {
                        Text(detail)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.88))
                            .lineLimit(5)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .help(detail)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.black.opacity(0.45)))
                    }

                    Spacer(minLength: 0)

                    buttons
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    /// MCP tools are "mcp__server__tool"; the tool part reads best.
    private var toolName: String {
        request.tool.components(separatedBy: "__").last ?? request.tool
    }

    private var buttons: some View {
        HStack(spacing: 6) {
            IslandIconButton(systemImage: "terminal", help: AppLocalization.string("agentHub.answerInTerminal")) {
                hub.answerInTerminal(request)
            }

            Spacer(minLength: 0)

            AgentActionButton(title: AppLocalization.string("agentHub.approval.deny"), tint: Color(red: 1, green: 0.55, blue: 0.59)) {
                BipSoundPlayer.shared.play(.close)
                hub.decide(.deny, for: request)
            }

            if request.canAlwaysAllow {
                AgentActionButton(title: AppLocalization.string("agentHub.approval.always")) {
                    BipSoundPlayer.shared.play(.received)
                    hub.decide(.alwaysAllow, for: request)
                }
            }

            AgentActionButton(title: AppLocalization.string("agentHub.approval.allow"), systemImage: "checkmark", isPrimary: true) {
                BipSoundPlayer.shared.play(.received)
                hub.decide(.allow, for: request)
            }
        }
    }
}

/// A question Claude asked. Hooks can't answer it, so the options are shown
/// and the user is taken to the terminal to pick one.
struct AgentQuestionCard: View {
    @ObservedObject var hub: AgentHubViewModel
    let session: AgentHubSession
    let question: AgentQuestion

    var body: some View {
        AgentWashCard(tint: AgentHubPhase.question.color) {
            HStack(alignment: .top, spacing: 12) {
                BipMascotView(mood: .question, size: 60)
                    .frame(maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 8) {
                    Text(AppLocalization.formatted("agentHub.question.caption", session.title))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AgentHubPhase.question.color)
                        .lineLimit(1)

                    Text(question.text)
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    if !question.options.isEmpty {
                        FlowRow(spacing: 5) {
                            ForEach(question.options, id: \.self) { option in
                                Text(option)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.white.opacity(0.08)))
                                    .overlay(Capsule().stroke(AgentHubPhase.question.color.opacity(0.35), lineWidth: 1))
                            }
                        }
                    }

                    Spacer(minLength: 0)

                    HStack {
                        Spacer()
                        AgentActionButton(
                            title: AppLocalization.string("agentHub.answerInTerminal"),
                            systemImage: "terminal",
                            isPrimary: true
                        ) {
                            hub.jumpToTerminal(sessionID: session.id)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}

/// The change DeskCast is about to make to Claude Code's settings, as a
/// diff, with Apply / Cancel. Nothing is written before Apply.
struct AgentHookChangeCard: View {
    @ObservedObject var hub: AgentHubViewModel

    var body: some View {
        AgentWashCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.badge.gearshape")
                        .foregroundStyle(.white.opacity(0.7))
                    Text(AppLocalization.string(hub.pendingChangeTitleKey))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("~/.claude/settings.json")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(IslandPalette.tertiaryText)
                }

                AgentDiffView(lines: hub.pendingHookChange?.diff ?? [])

                if let error = hub.hookError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }

                HStack(spacing: 6) {
                    Text(AppLocalization.string("agentHub.hooks.backupNote"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(IslandPalette.tertiaryText)
                        .lineLimit(2)
                    Spacer()
                    AgentActionButton(title: AppLocalization.string("agentHub.cancel")) {
                        hub.cancelPendingChange()
                    }
                    AgentActionButton(title: AppLocalization.string("agentHub.hooks.apply"), systemImage: "checkmark", isPrimary: true) {
                        hub.confirmPendingChange()
                    }
                }
            }
        }
    }
}

/// "+ added" / "- removed" lines, green and red.
struct AgentDiffView: View {
    let lines: [String]

    private static let added = Color(red: 0.45, green: 0.9, blue: 0.6)
    private static let removed = Color(red: 1, green: 0.5, blue: 0.55)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                if lines.isEmpty {
                    Text(AppLocalization.string("agentHub.hooks.noChange"))
                        .foregroundStyle(IslandPalette.secondaryText)
                }
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .foregroundStyle(line.hasPrefix("+") ? Self.added : Self.removed)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .font(.system(size: 10.5, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
        .padding(8)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.black.opacity(0.45)))
    }
}

/// Lays chips out in rows, wrapping to the next row when one is full.
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var origin = bounds.origin
        for row in arrange(subviews, width: bounds.width) {
            origin.x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: origin, proposal: ProposedViewSize(size))
                origin.x += size.width + spacing
            }
            origin.y += row.height + spacing
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row(indices: [index], width: size.width, height: size.height)
            } else {
                current = Row(indices: current.indices + [index], width: needed, height: max(current.height, size.height))
            }
        }
        if !current.indices.isEmpty {
            rows.append(current)
        }
        return rows
    }
}
