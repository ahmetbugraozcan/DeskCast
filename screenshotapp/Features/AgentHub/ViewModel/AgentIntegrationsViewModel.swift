import AppKit
import Combine

/// The Connections page: Stripe, Vercel, n8n, GitHub, Resend, Notion and
/// Cal.com, each read with the user's own key while turned on. New
/// payments, finished deployments and failed workflows are announced in the
/// island (the first reading only fills the page).
@MainActor
final class AgentIntegrationsViewModel: ObservableObject {
    @Published private(set) var snapshots: [AgentIntegration: IntegrationSnapshot] = [:]
    @Published private(set) var errors: [AgentIntegration: String] = [:]
    @Published private(set) var active: [AgentIntegration] = []
    @Published var selected: AgentIntegration?

    weak var presenter: AgentHubAttentionPresenting?

    private let client: IntegrationFetching
    private let secrets: AgentSecretStoring
    private let defaults: UserDefaults
    private var pollTasks: [AgentIntegration: Task<Void, Never>] = [:]
    /// Ids already seen per integration; `nil` until the first reading.
    private var seen: [AgentIntegration: Set<String>] = [:]
    private var defaultsObserver: AnyCancellable?

    init(client: IntegrationFetching? = nil, secrets: AgentSecretStoring? = nil, defaults: UserDefaults = .standard) {
        self.client = client ?? IntegrationClient()
        self.secrets = secrets ?? AgentKeychain()
        self.defaults = defaults
    }

    func start() {
        applySettings()
        defaultsObserver = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification, object: defaults)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applySettings()
            }
    }

    var focused: AgentIntegration? {
        selected.flatMap { active.contains($0) ? $0 : nil } ?? active.first
    }

    // MARK: - Settings

    func isEnabled(_ integration: AgentIntegration) -> Bool {
        (defaults.stringArray(forKey: AgentHubSettings.Keys.activeIntegrations) ?? []).contains(integration.rawValue)
    }

    func setEnabled(_ enabled: Bool, for integration: AgentIntegration) {
        var names = Set(defaults.stringArray(forKey: AgentHubSettings.Keys.activeIntegrations) ?? [])
        if enabled {
            names.insert(integration.rawValue)
        } else {
            names.remove(integration.rawValue)
        }
        defaults.set(AgentIntegration.allCases.map(\.rawValue).filter(names.contains), forKey: AgentHubSettings.Keys.activeIntegrations)
    }

    func hasKey(_ integration: AgentIntegration) -> Bool {
        secrets.value(for: integration.secret) != nil
    }

    func setKey(_ key: String?, for integration: AgentIntegration) {
        secrets.set(key, for: integration.secret)
        objectWillChange.send()
        restart(integration)
    }

    private func applySettings() {
        let wanted = AgentIntegration.allCases.filter { isEnabled($0) && hasKey($0) }
        guard wanted != active else { return }

        for integration in active where !wanted.contains(integration) {
            stop(integration)
        }
        for integration in wanted where !active.contains(integration) {
            startPolling(integration)
        }
        active = wanted
    }

    private func restart(_ integration: AgentIntegration) {
        stop(integration)
        active.removeAll { $0 == integration }
        applySettings()
    }

    private func stop(_ integration: AgentIntegration) {
        pollTasks.removeValue(forKey: integration)?.cancel()
        snapshots[integration] = nil
        errors[integration] = nil
        seen[integration] = nil
    }

    // MARK: - Polling

    private func startPolling(_ integration: AgentIntegration) {
        pollTasks[integration] = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh(integration)
                try? await Task.sleep(for: .seconds(integration.pollInterval))
            }
        }
    }

    func refresh(_ integration: AgentIntegration) async {
        guard let key = secrets.value(for: integration.secret) else { return }
        do {
            let snapshot = try await client.fetch(integration, key: key, baseURL: defaults.string(forKey: AgentHubSettings.Keys.n8nURL))
            guard !Task.isCancelled, active.contains(integration) || pollTasks[integration] != nil else { return }
            errors[integration] = nil
            announceNews(in: snapshot, for: integration)
            snapshots[integration] = snapshot
        } catch is CancellationError {
            return
        } catch {
            errors[integration] = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func refreshNow() {
        guard let focused else { return }
        Task { await refresh(focused) }
    }

    // MARK: - News

    private func announceNews(in snapshot: IntegrationSnapshot, for integration: AgentIntegration) {
        let finished = Self.finishedEvents(in: snapshot)
        let ids = Set(finished.map(\.id))
        defer { seen[integration, default: []].formUnion(ids) }
        // The first reading only fills the page.
        guard let known = seen[integration] else { return }

        for event in finished where !known.contains(event.id) {
            announce(event, integration: integration)
        }
    }

    /// Things worth announcing once: (id, title, failed).
    nonisolated struct Event {
        let id: String
        let title: String
        let failed: Bool
    }

    nonisolated static func finishedEvents(in snapshot: IntegrationSnapshot) -> [Event] {
        switch snapshot {
        case .stripe(let stripe):
            stripe.payments.filter(\.succeeded).map { payment in
                Event(id: payment.id, title: "+" + IntegrationFormat.money(payment.amount, currency: payment.currency), failed: false)
            }
        case .vercel(let deployments):
            deployments.filter(\.isFinished).map { deployment in
                Event(id: deployment.id, title: deployment.project, failed: !deployment.succeeded)
            }
        case .n8n(let executions):
            // Successful runs are routine; only failures are announced.
            executions.filter(\.failed).map { execution in
                Event(id: execution.id, title: execution.workflowName ?? "Workflow", failed: true)
            }
        default:
            []
        }
    }

    private func announce(_ event: Event, integration: AgentIntegration) {
        let title = AppLocalization.formatted(
            event.failed ? "agentHub.integrations.alert.failed" : "agentHub.integrations.alert.done",
            integration.name, event.title
        )
        BipSoundPlayer.shared.play(event.failed ? .error : .finished)
        presenter?.announce(
            DynamicIslandNotification(
                caption: integration.name,
                title: title,
                message: nil,
                systemImage: integration.systemImage,
                style: event.failed ? .warning : .success
            ),
            peek: title
        )
    }

    // MARK: - Actions

    func open(_ address: String) {
        let full = address.hasPrefix("http") ? address : "https://\(address)"
        guard let url = URL(string: full), url.scheme == "https" else { return }
        NSWorkspace.shared.open(url)
    }

    func openN8n(_ execution: N8nExecution) {
        guard let base = IntegrationClient.normalized(defaults.string(forKey: AgentHubSettings.Keys.n8nURL)) else { return }
        if let workflow = execution.workflowID {
            open("\(base)/workflow/\(workflow)/executions/\(execution.id)")
        } else {
            open(base)
        }
    }

    func retry(_ execution: N8nExecution) {
        guard let key = secrets.value(for: .n8n), let base = defaults.string(forKey: AgentHubSettings.Keys.n8nURL) else { return }
        Task {
            do {
                try await client.retryN8n(executionID: execution.id, key: key, baseURL: base)
                BipSoundPlayer.shared.play(.send)
                try? await Task.sleep(for: .seconds(2))
                await refresh(.n8n)
            } catch {
                errors[.n8n] = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

/// Money and short dates for the Connections page.
nonisolated enum IntegrationFormat {
    /// Minor units → "€12.50" (zero-decimal currencies like JPY stay whole).
    static func money(_ minorUnits: Int, currency: String) -> String {
        let code = currency.uppercased()
        let zeroDecimal: Set<String> = ["JPY", "KRW", "VND", "CLP", "ISK", "UGX", "XAF", "XOF"]
        let value = zeroDecimal.contains(code) ? Double(minorUnits) : Double(minorUnits) / 100
        return value.formatted(.currency(code: code).precision(.fractionLength(zeroDecimal.contains(code) ? 0 : 2)))
    }
}
