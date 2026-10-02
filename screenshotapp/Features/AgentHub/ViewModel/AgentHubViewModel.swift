import AppKit
import Combine

/// What the hub asks of the island; implemented by `DynamicIslandViewModel`
/// through `AgentHubIslandBridge` so this feature doesn't depend on it.
@MainActor
protocol AgentHubAttentionPresenting: AnyObject {
    var canShowAgentHub: Bool { get }
    func beginAgentAttention()
    func endAgentAttention()
    func announce(_ banner: DynamicIslandNotification, peek: String)
}

/// Follows Claude Code and Codex sessions through their hooks, holds
/// permission requests until the user answers them in the island, and
/// installs the hooks into Claude Code's settings or Codex's hooks file on
/// request.
@MainActor
final class AgentHubViewModel: ObservableObject {
    @Published private(set) var sessions: [AgentHubSession] = []
    /// Waiting permission requests, oldest first; the island shows the first.
    @Published private(set) var approvals: [AgentApprovalRequest] = []
    @Published private(set) var hooksInstalled = false
    @Published private(set) var codexHooksInstalled = false
    /// Codex is set up on this Mac (`~/.codex` exists).
    @Published private(set) var hasCodex = false
    /// A settings change waiting for the user's OK (shown as a diff).
    @Published private(set) var pendingHookChange: ClaudeHookChange?
    @Published private(set) var pendingChangeIsInstall = true
    @Published private(set) var pendingChangeTarget = AgentHookTarget.claudeCode
    @Published private(set) var hookError: String?
    /// The session the panel shows in detail.
    @Published var focusedSessionID: String?
    @Published var tab: AgentHubTab = .sessions
    /// The session a message is being typed for (the island takes keyboard
    /// focus only then).
    @Published private(set) var composingSessionID: String?
    @Published private(set) var isSendingReply = false
    @Published private(set) var replyFailed = false

    weak var presenter: AgentHubAttentionPresenting?
    /// Effects (finish, question…) for the mascot and sounds.
    let effects = PassthroughSubject<AgentHubEffect, Never>()

    private let server: AgentHookServing
    private let installer: ClaudeHookInstalling
    private let codexInstaller: ClaudeHookInstalling
    private let terminal: TerminalJumping
    private let defaults: UserDefaults
    private var state = AgentHubState()
    private var replies: [UUID: (String) -> Void] = [:]
    private var timeouts: [UUID: Task<Void, Never>] = [:]
    private var pruneTask: Task<Void, Never>?
    private var defaultsObserver: AnyCancellable?
    private var isRunning = false

    init(
        server: AgentHookServing? = nil,
        installer: ClaudeHookInstalling? = nil,
        codexInstaller: ClaudeHookInstalling? = nil,
        terminal: TerminalJumping? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.server = server ?? AgentHookServer()
        self.installer = installer ?? ClaudeHookInstallService()
        self.codexInstaller = codexInstaller ?? ClaudeHookInstallService(target: .codex)
        self.terminal = terminal ?? TerminalJumpService()
        self.defaults = defaults

        self.server.onEvent = { [weak self] event in
            self?.handle(event)
        }
        self.server.onPermissionRequest = { [weak self] event, reply in
            guard let self else {
                reply("")
                return
            }
            self.handlePermissionRequest(event, reply: reply)
        }
    }

    func start() {
        #if DEBUG
        // Screenshots: a made-up session, and no real hook events.
        if defaults.bool(forKey: "DeskCastDemoAgentSession") {
            runDemoSession()
            return
        }
        #endif
        refreshHookStatus()
        applySettings()
        defaultsObserver = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification, object: defaults)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applySettings()
            }
    }

    var pendingChangeTitleKey: String {
        let key = pendingChangeIsInstall ? "agentHub.hooks.reviewInstall" : "agentHub.hooks.reviewUninstall"
        return pendingChangeTarget == .codex ? key + ".codex" : key
    }

    var currentApproval: AgentApprovalRequest? {
        approvals.first
    }

    var focusedSession: AgentHubSession? {
        focusedSessionID.flatMap(state.session) ?? attentionSession ?? sessions.first
    }

    /// The first session that needs the user.
    var attentionSession: AgentHubSession? {
        if let approval = currentApproval, let session = state.session(approval.sessionID) {
            return session
        }
        return sessions.first { $0.phase.needsAttention }
    }

    var busySessions: [AgentHubSession] {
        sessions.filter { $0.phase.isBusy || $0.phase.needsAttention }
    }

    // MARK: - Approvals

    func decide(_ decision: AgentApprovalDecision, for request: AgentApprovalRequest? = nil) {
        guard let request = request ?? currentApproval else { return }
        resolve(request, output: decision.hookOutput(for: request))
    }

    /// Lets Claude Code ask in the terminal instead.
    func answerInTerminal(_ request: AgentApprovalRequest? = nil) {
        guard let request = request ?? currentApproval else { return }
        resolve(request, output: "")
        jumpToTerminal(sessionID: request.sessionID)
    }

    private func handlePermissionRequest(_ event: AgentHookEvent, reply: @escaping (String) -> Void) {
        state.apply(event)
        publish()

        guard isRunning, let presenter, presenter.canShowAgentHub else {
            reply("")
            return
        }

        // A newer request from the same session replaces an unanswered one.
        for stale in approvals where stale.sessionID == event.sessionID {
            resolve(stale, output: "", publishing: false)
        }

        let request = AgentApprovalRequest(event: event)
        approvals.append(request)
        replies[request.id] = reply
        let timeout = AgentHubSettings.approvalTimeout(in: defaults)
        timeouts[request.id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            self?.resolve(request, output: "")
        }

        focusedSessionID = event.sessionID
        tab = .sessions
        BipSoundPlayer.shared.play(.approval)
        effects.send(.question(sessionID: event.sessionID))
        if defaults.bool(forKey: AgentHubSettings.Keys.opensForAttention) {
            presenter.beginAgentAttention()
        }
    }

    private func resolve(_ request: AgentApprovalRequest, output: String, publishing: Bool = true) {
        timeouts.removeValue(forKey: request.id)?.cancel()
        replies.removeValue(forKey: request.id)?(output)
        approvals.removeAll { $0.id == request.id }
        state.resolveApproval(sessionID: request.sessionID)

        guard publishing else { return }
        publish()
        if approvals.isEmpty, !sessions.contains(where: { $0.phase == .question }) {
            presenter?.endAgentAttention()
        }
    }

    // MARK: - Events

    fileprivate func handle(_ event: AgentHookEvent) {
        // Any later event of a session means its pending request was answered
        // in the terminal (the permission notification itself comes after it).
        if event.kind != .notification, event.kind != .subagentStart, event.kind != .subagentStop {
            for request in approvals where request.sessionID == event.sessionID {
                resolve(request, output: "", publishing: false)
            }
        }

        let effect = state.apply(event)
        publish()
        if approvals.isEmpty, attentionSession == nil {
            presenter?.endAgentAttention()
        }

        guard let effect else { return }
        effects.send(effect)
        react(to: effect)
    }

    private func react(to effect: AgentHubEffect) {
        switch effect {
        case .question(let sessionID):
            focusedSessionID = sessionID
            tab = .sessions
            BipSoundPlayer.shared.play(.question)
            if defaults.bool(forKey: AgentHubSettings.Keys.opensForAttention) {
                presenter?.beginAgentAttention()
            }
        case .failed(let sessionID), .rateLimited(let sessionID):
            BipSoundPlayer.shared.play(.error)
            guard let session = state.session(sessionID) else { return }
            let title = AppLocalization.formatted(
                effect == .failed(sessionID: sessionID) ? "agentHub.alert.failed" : "agentHub.alert.rateLimited",
                session.title
            )
            presenter?.announce(
                DynamicIslandNotification(caption: session.title, title: title, message: session.lastMessage,
                                          systemImage: "exclamationmark.triangle.fill", style: .warning),
                peek: title
            )
        case .finished:
            // Long turns are announced by `AgentActivityMonitor`; here only
            // the mascot and the sound react.
            BipSoundPlayer.shared.play(.finished)
        }
    }

    func dismissResult(of sessionID: String) {
        state.settle(sessionID: sessionID)
        publish()
    }

    func jumpToTerminal(sessionID: String) {
        guard let session = state.session(sessionID) else { return }
        terminal.jump(to: session.terminal, cwd: session.cwd)
    }

    // MARK: - Messages

    /// Sessions in a Terminal or iTerm2 tab can be sent a message.
    func canReply(to session: AgentHubSession) -> Bool {
        terminal.canSendText(to: session.terminal)
    }

    func startReply(to sessionID: String) {
        replyFailed = false
        composingSessionID = sessionID
    }

    func cancelReply() {
        composingSessionID = nil
        replyFailed = false
    }

    /// Types the message into the session's terminal; Claude Code queues it
    /// if a turn is still running.
    func sendReply(_ text: String) {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !isSendingReply,
              let sessionID = composingSessionID, let session = state.session(sessionID) else { return }
        isSendingReply = true
        replyFailed = false
        Task {
            let sent = await terminal.sendText(message, to: session.terminal)
            isSendingReply = false
            if sent {
                composingSessionID = nil
            } else {
                replyFailed = true
            }
        }
    }

    private func publish() {
        state.pruneStale()
        sessions = state.sessions
        if let focusedSessionID, state.session(focusedSessionID) == nil {
            self.focusedSessionID = nil
        }
        if let composingSessionID, state.session(composingSessionID) == nil {
            self.composingSessionID = nil
        }
    }

    // MARK: - Settings and hooks

    private func applySettings() {
        let enabled = defaults.bool(forKey: AgentHubSettings.Keys.enabled)
        guard enabled != isRunning else { return }
        isRunning = enabled

        if enabled {
            try? AgentHookRelay.install()
            server.start()
            pruneTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                    self?.publish()
                }
            }
        } else {
            server.stop()
            pruneTask?.cancel()
            pruneTask = nil
            for request in approvals {
                resolve(request, output: "", publishing: false)
            }
            state = AgentHubState()
            publish()
            presenter?.endAgentAttention()
        }
    }

    func refreshHookStatus() {
        hooksInstalled = installer.isInstalled()
        codexHooksInstalled = codexInstaller.isInstalled()
        let codexFolder = AgentHookPaths.codexHooks.deletingLastPathComponent().path
        hasCodex = FileManager.default.fileExists(atPath: codexFolder)
    }

    private func installer(for target: AgentHookTarget) -> ClaudeHookInstalling {
        target == .codex ? codexInstaller : installer
    }

    func isInstalled(_ target: AgentHookTarget) -> Bool {
        target == .codex ? codexHooksInstalled : hooksInstalled
    }

    /// Whether the installed hooks wait as long as the setting asks.
    func hooksNeedUpdate(_ target: AgentHookTarget = .claudeCode) -> Bool {
        guard isInstalled(target), let timeout = installer(for: target).installedApprovalTimeout() else { return false }
        return timeout != AgentHubSettings.approvalTimeout(in: defaults) + 10
    }

    func prepareInstall(_ target: AgentHookTarget = .claudeCode) {
        prepare(target, isInstall: true) {
            try AgentHookRelay.install()
            return try installer(for: target).previewInstall(approvalTimeout: AgentHubSettings.approvalTimeout(in: defaults))
        }
    }

    func prepareUninstall(_ target: AgentHookTarget = .claudeCode) {
        prepare(target, isInstall: false) {
            try installer(for: target).previewUninstall()
        }
    }

    private func prepare(_ target: AgentHookTarget, isInstall: Bool, _ build: () throws -> ClaudeHookChange) {
        hookError = nil
        do {
            pendingChangeIsInstall = isInstall
            pendingChangeTarget = target
            pendingHookChange = try build()
        } catch {
            hookError = error.localizedDescription
        }
    }

    func confirmPendingChange() {
        guard let change = pendingHookChange else { return }
        do {
            try installer(for: pendingChangeTarget).apply(change)
            pendingHookChange = nil
        } catch {
            hookError = error.localizedDescription
        }
        refreshHookStatus()
    }

    func cancelPendingChange() {
        pendingHookChange = nil
    }
}

#if DEBUG
extension AgentHubViewModel {
    /// `-DeskCastDemoAgentSession YES`: a Claude Code turn in a Terminal tab
    /// that ran the tests and is now editing a file (live diff).
    fileprivate func runDemoSession() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("ForecastView.swift")
        try? """
        struct ForecastView: View {
            let report: WeatherReport

            var body: some View {
                VStack(alignment: .leading) {
                    Text(report.city).font(.title2)
                    CurrentConditions(report.current)
                }
            }
        }
        """.write(to: file, atomically: true, encoding: .utf8)

        let base: [String: Any] = [
            "session_id": "demo",
            "cwd": "/Users/demo/Projects/weather-app",
            "term_program": "Apple_Terminal",
            "tty": "/dev/ttys009"
        ]
        let events: [[String: Any]] = [
            ["hook_event_name": "UserPromptSubmit", "prompt": "Add a 7-day forecast under the current conditions"],
            ["hook_event_name": "PreToolUse", "tool_name": "Read", "tool_input": ["file_path": file.path]],
            ["hook_event_name": "PostToolUse", "tool_name": "Read", "tool_input": ["file_path": file.path]],
            ["hook_event_name": "PreToolUse", "tool_name": "Bash", "tool_input": ["command": "swift test --filter Forecast"]],
            [
                "hook_event_name": "PostToolUse", "tool_name": "Bash", "tool_input": ["command": "swift test --filter Forecast"],
                "tool_response": ["stdout": "Test Suite 'ForecastTests' passed.\n  Executed 6 tests, with 0 failures in 0.042 s"]
            ],
            [
                "hook_event_name": "PreToolUse", "tool_name": "Edit",
                "tool_input": [
                    "file_path": file.path,
                    "old_string": "            CurrentConditions(report.current)\n",
                    "new_string": "            CurrentConditions(report.current)\n            Divider()\n"
                        + "            DailyForecastList(days: report.daily.prefix(7))\n"
                ]
            ]
        ]
        for event in events {
            if let decoded = AgentHookEvent(payload: base.merging(event) { _, new in new }) {
                handle(decoded)
            }
        }
    }
}
#endif
