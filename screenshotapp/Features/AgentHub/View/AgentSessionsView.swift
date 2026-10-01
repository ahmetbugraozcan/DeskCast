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
                    Text(session.projectName == nil
                         ? AppLocalization.string(session.phase.titleKey)
                         : "\(session.agentName) · \(AppLocalization.string(session.phase.titleKey))")
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
                    if hub.composingSessionID == session.id {
                        AgentReplyBar(hub: hub, agentName: session.agentName)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
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
                .truncationMode(.middle)
                .help(session.cwd)
            if session.projectName != nil {
                Text(session.agentName)
                    .font(.system(size: 11))
                    .foregroundStyle(IslandPalette.tertiaryText)
                    .lineLimit(1)
                    .fixedSize()
            }

            Spacer(minLength: 4)

            Group {
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
            }
            .fixedSize()

            if hub.canReply(to: session), hub.composingSessionID != session.id {
                let help = AppLocalization.formatted("agentHub.reply.help", session.agentName)
                IslandIconButton(systemImage: "text.bubble", help: help, size: 11) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { hub.startReply(to: session.id) }
                }
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
            AgentTerminalBox(run: run, isRunning: isStepRunning && run.output.isEmpty)
            Spacer(minLength: 0)
        } else if let change = session.codeChange {
            AgentCodeDiffView(change: change, isLive: isStepRunning && session.currentStep?.isEdit == true)
        } else {
            promptBubble
            Spacer(minLength: 0)
        }
    }

    /// The last tool is still running (not just Claude thinking after it).
    private var isStepRunning: Bool {
        session.phase.isBusy && session.currentStep?.isFinished == false
    }

    @ViewBuilder
    private var currentStepLine: some View {
        if session.phase.isBusy, let step = session.turnSteps.last, step.isFinished {
            AgentShimmerText(text: AppLocalization.string("agentHub.phase.thinking"), size: 12.5)
        } else if let step = session.turnSteps.last {
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

// MARK: - Reply

/// Types a message into the session's terminal tab (Terminal / iTerm2).
private struct AgentReplyBar: View {
    @ObservedObject var hub: AgentHubViewModel
    let agentName: String

    @State private var text = ""
    @FocusState private var isFocused: Bool

    private var canSend: Bool {
        !hub.isSendingReply && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                TextField(AppLocalization.formatted("agentHub.reply.placeholder", agentName), text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white)
                    .focused($isFocused)
                    .onSubmit(send)
                    .onExitCommand(perform: hub.cancelReply)

                IslandIconButton(systemImage: "xmark", help: AppLocalization.string("agentHub.close"), size: 10) {
                    withAnimation(.easeOut(duration: 0.2)) { hub.cancelReply() }
                }

                Button(action: send) {
                    Group {
                        if hub.isSendingReply {
                            ProgressView().controlSize(.mini).tint(.black)
                        } else {
                            Image(systemName: "arrow.up").font(.system(size: 11, weight: .bold))
                        }
                    }
                    .foregroundStyle(canSend ? Color.black : Color.white.opacity(0.4))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(canSend || hub.isSendingReply ? Color.white : Color.white.opacity(0.1)))
                }
                .buttonStyle(IslandScaleButtonStyle())
                .disabled(!canSend)
            }
            .padding(.leading, 10)
            .padding(.trailing, 4)
            .padding(.vertical, 4)
            .background(Capsule().fill(IslandPalette.card))
            .overlay(Capsule().stroke(Color.white.opacity(isFocused ? 0.2 : 0.08), lineWidth: 1))

            if hub.replyFailed {
                Text(AppLocalization.string("agentHub.reply.failed"))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color(red: 1, green: 0.55, blue: 0.59))
            }
        }
        .onAppear {
            // The island becomes key a moment after composing starts.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { isFocused = true }
        }
    }

    private func send() {
        guard canSend else { return }
        hub.sendReply(text)
        text = ""
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
