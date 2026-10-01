import SwiftUI

extension AgentIntegration {
    var color: Color { Color(red: tint.red, green: tint.green, blue: tint.blue) }
}

/// The Connections page: the turned-on services on the left (each with its
/// own colored Bip), the selected one's latest reading on the right.
struct AgentIntegrationsView: View {
    @ObservedObject var model: AgentIntegrationsViewModel
    let openSettings: () -> Void

    var body: some View {
        if model.active.isEmpty {
            AgentWashCard {
                HStack(spacing: 16) {
                    BipMascotView(mood: .sleeping, size: 72)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(AppLocalization.string("agentHub.integrations.emptyTitle"))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                        Text(AppLocalization.string("agentHub.integrations.emptyMessage"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(IslandPalette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        AgentActionButton(
                            title: AppLocalization.string("agentHub.integrations.connect"), systemImage: "gearshape", isPrimary: true,
                            action: openSettings
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)
            }
        } else {
            HStack(spacing: 8) {
                list
                    .frame(width: 148)
                if let focused = model.focused {
                    AgentIntegrationDetail(model: model, integration: focused)
                        .id(focused)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: model.focused)
        }
    }

    private var list: some View {
        IslandCard(padding: 6) {
            VStack(spacing: 4) {
                ForEach(model.active) { integration in
                    let isFocused = model.focused == integration
                    Button {
                        model.selected = integration
                    } label: {
                        HStack(spacing: 7) {
                            BipMascotView(mood: mood(of: integration), size: 24, tint: integration.tint, isInteractive: false)
                            Text(integration.name)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(.white)
                            Spacer(minLength: 0)
                            if model.errors[integration] != nil {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding(.horizontal, 6)
                        .frame(height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isFocused ? integration.color.opacity(0.18) : .clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func mood(of integration: AgentIntegration) -> BipMood {
        if model.errors[integration] != nil { return .error }
        if model.snapshots[integration] == nil { return .thinking }
        if case .n8n(let runs) = model.snapshots[integration], runs.first?.failed == true { return .error }
        if case .vercel(let deployments) = model.snapshots[integration], deployments.first?.isFinished == false { return .working }
        return .idle
    }
}

/// One service's card.
private struct AgentIntegrationDetail: View {
    @ObservedObject var model: AgentIntegrationsViewModel
    let integration: AgentIntegration

    var body: some View {
        AgentWashCard(tint: integration.color.opacity(0.6), padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: integration.systemImage)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(integration.color)
                    Text(integration.name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    IslandIconButton(
                        systemImage: "arrow.clockwise", help: AppLocalization.string("agentHub.integrations.refresh"), size: 11
                    ) {
                        model.refreshNow()
                    }
                }

                if let error = model.errors[integration] {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let snapshot = model.snapshots[integration] {
                    content(snapshot)
                } else if model.errors[integration] == nil {
                    AgentShimmerText(text: AppLocalization.string("agentHub.integrations.loading"), size: 12)
                }

                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private func content(_ snapshot: IntegrationSnapshot) -> some View {
        switch snapshot {
        case .stripe(let stripe):
            AgentStripeContent(stripe: stripe)
        case .vercel(let deployments):
            rows(deployments.prefix(4).map { deployment in
                AgentIntegrationRow(
                    title: deployment.project,
                    detail: deployment.commit ?? deployment.branch,
                    date: deployment.date,
                    status: deployment.succeeded ? .good : (deployment.isFinished ? .bad : .busy),
                    action: { model.open(deployment.url) }
                )
            })
        case .n8n(let executions):
            rows(executions.prefix(4).map { execution in
                AgentIntegrationRow(
                    title: execution.workflowName ?? "Workflow #\(execution.workflowID ?? "?")",
                    detail: execution.status,
                    date: execution.date,
                    status: execution.failed ? .bad : (execution.isFinished ? .good : .busy),
                    action: { model.openN8n(execution) },
                    retry: execution.failed ? { model.retry(execution) } : nil
                )
            })
        case .resend(let emails, let total):
            if let total {
                Text(AppLocalization.formatted("agentHub.integrations.resendTotal", total))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(IslandPalette.secondaryText)
            }
            rows(emails.prefix(4).map { email in
                AgentIntegrationRow(
                    title: email.subject.isEmpty ? "—" : email.subject,
                    detail: email.recipients.first.map { "\($0) · \(email.lastEvent)" } ?? email.lastEvent,
                    date: email.date,
                    status: ["bounced", "complained", "failed"].contains(email.lastEvent) ? .bad : .good
                )
            })
        case .github(let summary):
            AgentGitHubContent(summary: summary) { model.open("github.com/\(summary.login)") }
        case .notion(let pages):
            rows(pages.prefix(4).map { page in
                AgentIntegrationRow(
                    title: [page.emoji, page.title].compactMap(\.self).joined(separator: " "), detail: nil, date: page.date,
                    action: { model.open(page.url) }
                )
            })
        case .calcom(let bookings):
            if bookings.isEmpty {
                Text(AppLocalization.string("agentHub.integrations.noBookings"))
                    .font(.system(size: 12))
                    .foregroundStyle(IslandPalette.secondaryText)
            }
            rows(bookings.prefix(4).map { booking in
                AgentIntegrationRow(
                    title: booking.title,
                    detail: [booking.start.formatted(date: .abbreviated, time: .shortened), booking.attendee]
                        .compactMap(\.self).joined(separator: " · "),
                    date: nil
                )
            })
        }
    }

    private func rows(_ rows: [AgentIntegrationRow]) -> some View {
        VStack(spacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                row
            }
        }
    }
}

/// A line in a service card: status dot, title, detail, time.
private struct AgentIntegrationRow: View {
    enum Status {
        case good
        case bad
        case busy
        case none
    }

    let title: String
    let detail: String?
    let date: Date?
    var status: Status = .none
    var action: (() -> Void)?
    var retry: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .opacity(status == .none ? 0 : 1)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(IslandPalette.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if let retry {
                IslandChipButton(
                    title: AppLocalization.string("agentHub.integrations.retry"), systemImage: "arrow.clockwise", action: retry
                )
            }
            if let date {
                Text(IslandFormat.relative(date))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(IslandPalette.tertiaryText)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.04)))
        .contentShape(Rectangle())
        .onTapGesture { action?() }
    }

    private var color: Color {
        switch status {
        case .good: AgentHubPhase.finished.color
        case .bad: AgentHubPhase.error.color
        case .busy: AgentHubPhase.working.color
        case .none: .clear
        }
    }
}

private struct AgentStripeContent: View {
    let stripe: StripeSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            IslandRollingText(
                text: IntegrationFormat.money(stripe.balance, currency: stripe.currency),
                value: Double(stripe.balance),
                size: 24,
                weight: .bold
            )
            Text(AppLocalization.string("agentHub.integrations.balance"))
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(IslandPalette.tertiaryText)

            ForEach(stripe.payments.prefix(3)) { payment in
                AgentIntegrationRow(
                    title: IntegrationFormat.money(payment.amount, currency: payment.currency),
                    detail: payment.summary,
                    date: payment.date,
                    status: payment.succeeded ? .good : .bad
                )
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: stripe.payments.map(\.id))
    }
}

private struct AgentGitHubContent: View {
    let summary: GitHubSummary
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: open) {
                Text("@\(summary.login)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .buttonStyle(.plain)

            HStack(spacing: 18) {
                stat(summary.repositories, "agentHub.integrations.repos")
                stat(summary.stars, "agentHub.integrations.stars")
                stat(summary.followers, "agentHub.integrations.followers")
            }
        }
    }

    private func stat(_ value: Int, _ key: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            IslandRollingText(text: "\(value)", value: Double(value), size: 22, weight: .bold)
            Text(AppLocalization.string(key))
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(IslandPalette.tertiaryText)
        }
    }
}
