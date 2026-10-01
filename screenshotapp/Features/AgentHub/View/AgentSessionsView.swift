import SwiftUI

/// The Sessions page: a permission request or question when one is waiting,
/// otherwise the focused session's live feed, with every session listed on
/// the right.
struct AgentSessionsView: View {
    @ObservedObject var hub: AgentHubViewModel

    var body: some View {
        HStack(spacing: 8) {
            mainCard
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if hub.sessions.count > 1 {
                AgentSessionList(hub: hub)
                    .frame(width: 148)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: hub.sessions.map(\.id))
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: hub.currentApproval?.id)
    }

    @ViewBuilder
    private var mainCard: some View {
        if hub.pendingHookChange != nil {
            AgentHookChangeCard(hub: hub)
        } else if let approval = hub.currentApproval {
            AgentApprovalCard(hub: hub, request: approval, session: hub.sessions.first { $0.id == approval.sessionID })
                .id(approval.id)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
        } else if let session = hub.focusedSession {
            if session.phase == .question, let question = session.question {
                AgentQuestionCard(hub: hub, session: session, question: question)
            } else {
                AgentSessionCard(hub: hub, session: session)
                    .id(session.id)
                    .transition(.opacity)
            }
        } else {
            AgentEmptyCard(hub: hub)
        }
    }
}

// MARK: - Session list

private struct AgentSessionList: View {
    @ObservedObject var hub: AgentHubViewModel

    var body: some View {
        IslandCard(padding: 6) {
            VStack(spacing: 4) {
                ForEach(hub.sessions) { session in
                    row(session)
                }
            }
        }
    }

    private func row(_ session: AgentHubSession) -> some View {
        let isFocused = hub.focusedSession?.id == session.id

        return Button {
            hub.focusedSessionID = session.id
        } label: {
            HStack(spacing: 7) {
                BipMascotView(mood: BipMood(phase: session.phase), size: 24, isInteractive: false)

                VStack(alignment: .leading, spacing: 1) {
                    Text(session.title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(AppLocalization.string(session.phase.titleKey))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(session.phase.color)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isFocused ? session.phase.color.opacity(0.16) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Session

/// A session at a glance: Bip with the turn's checklist on the left; on the
/// right the current step and, below it, the edit as a diff or the last
/// command with its output, or the result once the turn is over.
private struct AgentSessionCard: View {
    @ObservedObject var hub: AgentHubViewModel
    let session: AgentHubSession

    @State private var showsFullMessage = false

    private var tint: Color? {
        switch session.phase {
        case .finished, .error, .rateLimited: session.phase.color
        default: nil
        }
    }

    private var isOver: Bool {
        session.phase == .finished || session.phase == .error || session.phase == .rateLimited
    }

    var body: some View {
        AgentWashCard(tint: tint, padding: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 10) {
                    BipMascotView(mood: BipMood(phase: session.phase), size: 54)
                        .frame(maxWidth: .infinity)
                    AgentStepChecklist(session: session)
                    Spacer(minLength: 0)
                }
                .frame(width: 92)

                VStack(alignment: .leading, spacing: 7) {
                    header
                    if isOver {
                        resultBody
                    } else {
                        liveBody
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Circle().fill(session.phase.color).frame(width: 7, height: 7)
            Text(session.title)
                .font(.system(size: 13.5, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .layoutPriority(1)
            Text(session.agent == "codex" ? "Codex" : "Claude Code")
                .font(.system(size: 11))
                .foregroundStyle(IslandPalette.tertiaryText)
                .lineLimit(1)

            Spacer(minLength: 4)

            if let started = session.turnStartedAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(IslandFormat.clock(context.date.timeIntervalSince(started)))
                        .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(IslandPalette.secondaryText)
                }
            } else if !session.turnSteps.isEmpty {
                Text(AppLocalization.formatted("agentHub.steps", session.turnSteps.count))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(IslandPalette.tertiaryText)
            }

            IslandIconButton(systemImage: "arrow.up.forward.app", help: openTitle, size: 11) {
                hub.jumpToTerminal(sessionID: session.id)
            }
        }
    }

    // MARK: Working

    @ViewBuilder
    private var liveBody: some View {
        currentStepLine

        if session.showsCommand, let run = session.command {
            AgentTerminalBox(run: run, isRunning: session.phase.isBusy && run.output.isEmpty)
            Spacer(minLength: 0)
        } else if let change = session.codeChange {
            AgentCodeDiffView(change: change, isLive: session.phase.isBusy && session.currentStep?.isEdit == true)
        } else {
            promptBubble
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var currentStepLine: some View {
        if let step = session.turnSteps.last {
            HStack(spacing: 6) {
                Image(systemName: step.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(session.phase.isBusy ? session.phase.color : IslandPalette.secondaryText)
                    .frame(width: 14)
                if session.phase.isBusy {
                    AgentShimmerText(text: step.text, size: 12.5)
                } else {
                    Text(step.text)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                }
            }
            .id(step.id)
            .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
        } else if session.phase == .idle {
            Text(AppLocalization.string("agentHub.waitingForPrompt"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(IslandPalette.secondaryText)
        } else {
            AgentShimmerText(text: AppLocalization.string("agentHub.phase.thinking"), size: 12.5)
        }
    }

    @ViewBuilder
    private var promptBubble: some View {
        if let prompt = session.steps.last(where: { $0.kind == .prompt }) {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "quote.opening")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(IslandPalette.tertiaryText)
                    .padding(.top, 2)
                Text(prompt.detail ?? AppLocalization.string("agentHub.step.prompt"))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(4)
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.05)))
        }
    }

    // MARK: Result

    private var resultBody: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: session.phase == .finished ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(session.phase.color)
                Text(AppLocalization.string(session.phase.titleKey))
                    .foregroundStyle(session.phase.color)
            }
            .font(.system(size: 12.5, weight: .semibold))

            if showsFullMessage, let message = session.lastMessage {
                ScrollView(showsIndicators: false) {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            } else {
                if let message = session.lastMessage {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(session.phase == .error ? Color(red: 1, green: 0.55, blue: 0.59) : .white.opacity(0.8))
                        .lineLimit(session.command == nil ? 5 : 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let run = session.command {
                    AgentTerminalBox(run: run, maxOutputLines: 2)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                if (session.lastMessage?.count ?? 0) > 120 {
                    Button(AppLocalization.string(showsFullMessage ? "agentHub.showLess" : "agentHub.showMore")) {
                        withAnimation(.easeOut(duration: 0.2)) { showsFullMessage.toggle() }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(IslandPalette.secondaryText)
                }
                Spacer()
                AgentActionButton(title: openTitle, systemImage: openSymbol) {
                    hub.jumpToTerminal(sessionID: session.id)
                }
                AgentActionButton(title: AppLocalization.string("agentHub.close"), isPrimary: true) {
                    hub.dismissResult(of: session.id)
                }
            }
        }
    }

    // MARK: Opening the session

    /// Sessions without a terminal run in the Claude (or Codex) app.
    private var runsInApp: Bool {
        session.terminal.termProgram.isEmpty && session.terminal.tty.isEmpty
    }

    private var openTitle: String {
        guard runsInApp else { return AppLocalization.string("agentHub.openTerminal") }
        return AppLocalization.string(session.agent == "codex" ? "agentHub.openCodex" : "agentHub.openClaude")
    }

    private var openSymbol: String {
        runsInApp ? "arrow.up.forward.app" : "terminal"
    }
}

// MARK: - Empty

private struct AgentEmptyCard: View {
    @ObservedObject var hub: AgentHubViewModel

    var body: some View {
        AgentWashCard {
            HStack(spacing: 16) {
                BipMascotView(mood: hub.hooksInstalled ? .idle : .sleeping, size: 76)

                VStack(alignment: .leading, spacing: 8) {
                    Text(AppLocalization.string(hub.hooksInstalled ? "agentHub.empty.title" : "agentHub.setup.title"))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)

                    Text(AppLocalization.string(hub.hooksInstalled ? "agentHub.empty.message" : "agentHub.setup.message"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(IslandPalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    if let error = hub.hookError {
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                            .lineLimit(2)
                    }

                    HStack(spacing: 6) {
                        if hub.hooksInstalled {
                            AgentActionButton(
                                title: AppLocalization.string("agentHub.empty.ask"), systemImage: "sparkles", isPrimary: true
                            ) {
                                hub.tab = .ask
                            }
                        } else {
                            AgentActionButton(
                                title: AppLocalization.string("agentHub.setup.install"), systemImage: "link", isPrimary: true
                            ) {
                                hub.prepareInstall()
                            }
                        }
                        if hub.hasCodex, !hub.codexHooksInstalled {
                            AgentActionButton(title: AppLocalization.string("agentHub.setup.installCodex"), systemImage: "link") {
                                hub.prepareInstall(.codex)
                            }
                        }
                    }
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
        }
    }
}
