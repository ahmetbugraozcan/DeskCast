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

            if !hub.sessions.isEmpty {
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

private struct AgentSessionCard: View {
    @ObservedObject var hub: AgentHubViewModel
    let session: AgentHubSession

    private var tint: Color? {
        switch session.phase {
        case .finished, .error, .rateLimited, .thinking: session.phase.color
        default: nil
        }
    }

    var body: some View {
        AgentWashCard(tint: tint) {
            HStack(alignment: .top, spacing: 12) {
                BipMascotView(mood: BipMood(phase: session.phase), size: 64)
                    .frame(maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 8) {
                    header

                    switch session.phase {
                    case .finished, .error, .rateLimited:
                        resultBody
                    default:
                        AgentStepTicker(session: session)
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
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(AppLocalization.string(session.phase.titleKey))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(session.phase.color)
                .lineLimit(1)

            Spacer(minLength: 4)

            if let started = session.turnStartedAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(IslandFormat.clock(context.date.timeIntervalSince(started)))
                        .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(IslandPalette.secondaryText)
                }
            }

            IslandIconButton(
                systemImage: "arrow.up.forward.app",
                help: AppLocalization.string("agentHub.openTerminal"),
                size: 11
            ) {
                hub.jumpToTerminal(sessionID: session.id)
            }
        }
    }

    private var resultBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session.lastMessage ?? AppLocalization.string("agentHub.finished.noSummary"))
                .font(.system(size: 12.5))
                .foregroundStyle(session.phase == .error ? Color(red: 1, green: 0.55, blue: 0.59) : .white.opacity(0.88))
                .lineLimit(7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Spacer()
                AgentActionButton(title: AppLocalization.string("agentHub.openTerminal"), systemImage: "terminal") {
                    hub.jumpToTerminal(sessionID: session.id)
                }
                AgentActionButton(title: AppLocalization.string("agentHub.ok"), isPrimary: true) {
                    hub.dismissResult(of: session.id)
                }
            }
        }
    }
}

/// The last few steps, newest at the bottom and gliding up as new ones arrive.
private struct AgentStepTicker: View {
    let session: AgentHubSession

    var body: some View {
        let prompt = session.steps.last { $0.kind == .prompt }
        let steps = Array(session.steps.filter { $0.kind != .prompt }.suffix(4))

        VStack(alignment: .leading, spacing: 10) {
            if let prompt {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(IslandPalette.tertiaryText)
                        .padding(.top, 2)
                    Text(prompt.detail ?? AppLocalization.string("agentHub.step.prompt"))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(3)
                }
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.05)))
            }

            Spacer(minLength: 0)

            ticker(steps)
        }
    }

    private func ticker(_ steps: [AgentHubStep]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if steps.isEmpty, session.phase == .idle {
                Text(AppLocalization.string("agentHub.waitingForPrompt"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(IslandPalette.secondaryText)
            }

            ForEach(steps) { step in
                let isCurrent = step.id == steps.last?.id && session.phase.isBusy
                HStack(spacing: 7) {
                    Image(systemName: step.systemImage)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(isCurrent ? session.phase.color : IslandPalette.tertiaryText)
                        .frame(width: 14)

                    if isCurrent {
                        AgentShimmerText(text: step.text, size: 13)
                    } else {
                        Text(step.text)
                            .font(.system(size: 12))
                            .foregroundStyle(step.id == steps.last?.id ? .white.opacity(0.8) : IslandPalette.tertiaryText)
                            .lineLimit(1)
                    }
                }
                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .bottomLeading)
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: steps.map(\.id))
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
                    }
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
        }
    }
}
