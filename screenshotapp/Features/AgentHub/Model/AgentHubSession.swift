import Foundation

/// What an agent session is doing, as its hooks report it.
nonisolated enum AgentHubPhase: String, CaseIterable, Sendable {
    case idle
    case thinking
    case working
    case approval
    case question
    case error
    case finished
    case rateLimited

    /// The session needs the user (shown first, opens the island).
    var needsAttention: Bool {
        self == .approval || self == .question || self == .error
    }

    var isBusy: Bool {
        self == .thinking || self == .working
    }
}

/// One line of a session's activity feed.
nonisolated struct AgentHubStep: Identifiable, Equatable, Sendable {
    nonisolated enum Kind: Equatable, Sendable {
        case prompt
        case tool(String)
        case failed(String)
        case subagentStarted
        case subagentFinished
    }

    let id: UUID
    let kind: Kind
    let detail: String?
    let date: Date

    init(kind: Kind, detail: String?, date: Date, id: UUID = UUID()) {
        self.id = id
        self.kind = kind
        self.detail = detail
        self.date = date
    }
}

/// A Claude Code session (or another agent using the relay) followed
/// through its hooks.
nonisolated struct AgentHubSession: Identifiable, Equatable, Sendable {
    let id: String
    var agent: String?
    var cwd: String
    var phase: AgentHubPhase = .idle
    var steps: [AgentHubStep] = []
    var terminal = AgentTerminalContext()
    /// The end of the last answer (Stop), or the error (StopFailure).
    var lastMessage: String?
    var question: AgentQuestion?
    var turnStartedAt: Date?
    var updatedAt: Date
    /// The last edit of this turn, shown as a diff.
    var codeChange: AgentCodeChange?
    /// The last shell command of this turn and its output.
    var command: AgentCommandRun?
    /// Which of the two came last (the island shows that one).
    var showsCommand = false

    static let maxSteps = 20

    /// The working directory's name, or the agent's own name.
    var title: String {
        let folder = URL(fileURLWithPath: cwd).lastPathComponent
        if let agent {
            let name = agent == "codex" ? "Codex" : agent
            return folder.isEmpty || folder == "/" ? name : "\(name) · \(folder)"
        }
        return folder.isEmpty || folder == "/" ? "Claude Code" : folder
    }

    var currentStep: AgentHubStep? {
        steps.last
    }

    /// The tool steps since the last prompt.
    var turnSteps: [AgentHubStep] {
        let start = steps.lastIndex { $0.kind == .prompt }.map { steps.index(after: $0) } ?? steps.startIndex
        return Array(steps[start...])
    }

    mutating func append(_ step: AgentHubStep) {
        steps.append(step)
        if steps.count > Self.maxSteps {
            steps.removeFirst(steps.count - Self.maxSteps)
        }
    }
}

/// Something worth telling the user about, produced by `AgentHubState.apply`.
nonisolated enum AgentHubEffect: Equatable, Sendable {
    case question(sessionID: String)
    case finished(sessionID: String, duration: TimeInterval)
    case failed(sessionID: String)
    case rateLimited(sessionID: String)
}

/// All followed sessions, most recently active first. Pure: the view model
/// feeds it hook events and reacts to the effects.
nonisolated struct AgentHubState: Equatable, Sendable {
    private(set) var sessions: [AgentHubSession] = []

    static let maxSessions = 6
    /// Quiet sessions drop out of the list after this long.
    static let staleInterval: TimeInterval = 30 * 60

    func session(_ id: String) -> AgentHubSession? {
        sessions.first { $0.id == id }
    }

    @discardableResult
    mutating func apply(_ event: AgentHookEvent, now: Date = Date()) -> AgentHubEffect? {
        if event.kind == .sessionEnd {
            sessions.removeAll { $0.id == event.sessionID }
            return nil
        }

        var session = takeSession(for: event, now: now)
        defer { insert(session) }
        return Self.update(&session, with: event, now: now)
    }

    /// The user answered a permission request (here or in the terminal).
    mutating func resolveApproval(sessionID: String, now: Date = Date()) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }),
              sessions[index].phase == .approval else {
            return
        }
        sessions[index].phase = .working
        sessions[index].updatedAt = now
    }

    /// Shows a finished/failed session as idle again once its card was seen.
    mutating func settle(sessionID: String, now: Date = Date()) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }),
              sessions[index].phase == .finished || sessions[index].phase == .error || sessions[index].phase == .rateLimited else {
            return
        }
        sessions[index].phase = .idle
        sessions[index].updatedAt = now
    }

    mutating func pruneStale(now: Date = Date()) {
        sessions.removeAll { session in
            !session.phase.needsAttention && now.timeIntervalSince(session.updatedAt) > Self.staleInterval
        }
    }

    private mutating func takeSession(for event: AgentHookEvent, now: Date) -> AgentHubSession {
        var session: AgentHubSession
        if let index = sessions.firstIndex(where: { $0.id == event.sessionID }) {
            session = sessions.remove(at: index)
        } else {
            session = AgentHubSession(id: event.sessionID, agent: event.agent, cwd: event.cwd, updatedAt: now)
        }

        if !event.cwd.isEmpty {
            session.cwd = event.cwd
        }
        session.terminal = event.terminal.merged(with: session.terminal)
        session.updatedAt = now
        return session
    }

    private mutating func insert(_ session: AgentHubSession) {
        sessions.insert(session, at: 0)
        if sessions.count > Self.maxSessions {
            sessions.removeLast(sessions.count - Self.maxSessions)
        }
    }

    private static func update(_ session: inout AgentHubSession, with event: AgentHookEvent, now: Date) -> AgentHubEffect? {
        switch event.kind {
        case .sessionStart, .sessionEnd:
            if session.phase.isBusy == false, session.phase != .approval {
                session.phase = .idle
            }
            return nil
        case .userPromptSubmit:
            session.phase = .thinking
            session.turnStartedAt = now
            session.lastMessage = nil
            session.question = nil
            session.codeChange = nil
            session.command = nil
            session.showsCommand = false
            session.append(AgentHubStep(kind: .prompt, detail: event.prompt, date: now))
            return nil
        case .preToolUse:
            return startTool(&session, event: event, now: now)
        case .postToolUse:
            session.question = nil
            session.phase = .working
            recordOutput(&session, event: event, failed: false)
            return nil
        case .postToolUseFailure:
            session.phase = .working
            recordOutput(&session, event: event, failed: true)
            session.append(AgentHubStep(kind: .failed(event.toolName ?? "Tool"), detail: event.toolSummary, date: now))
            return nil
        case .permissionRequest:
            session.phase = .approval
            return nil
        case .notification:
            guard Self.isRateLimit(event.message) else { return nil }
            session.phase = .rateLimited
            return .rateLimited(sessionID: session.id)
        case .stop:
            return finish(&session, event: event, now: now)
        case .interrupt:
            session.phase = .idle
            session.question = nil
            session.turnStartedAt = nil
            return nil
        case .stopFailure:
            session.lastMessage = event.message
            session.turnStartedAt = nil
            if event.errorType == "rate_limit" {
                session.phase = .rateLimited
                return .rateLimited(sessionID: session.id)
            }
            session.phase = .error
            return .failed(sessionID: session.id)
        case .subagentStart:
            session.append(AgentHubStep(kind: .subagentStarted, detail: nil, date: now))
            return nil
        case .subagentStop:
            session.append(AgentHubStep(kind: .subagentFinished, detail: nil, date: now))
            return nil
        }
    }

    private static func startTool(_ session: inout AgentHubSession, event: AgentHookEvent, now: Date) -> AgentHubEffect? {
        if session.turnStartedAt == nil {
            session.turnStartedAt = now
        }

        if let question = event.question {
            session.phase = .question
            session.question = question
            return .question(sessionID: session.id)
        }

        session.phase = .working
        session.append(AgentHubStep(kind: .tool(event.toolName ?? "Tool"), detail: event.toolSummary, date: now))
        if let change = event.codeChange {
            session.codeChange = change
            session.showsCommand = false
        } else if event.toolName == AgentHookEvent.shellTool, let command = event.command {
            session.command = AgentCommandRun(command: AgentHookEvent.singleLine(command))
            session.showsCommand = true
        }
        return nil
    }

    private static func recordOutput(_ session: inout AgentHubSession, event: AgentHookEvent, failed: Bool) {
        guard event.toolName == AgentHookEvent.shellTool, let output = event.commandOutput else { return }
        let command = event.command.map(AgentHookEvent.singleLine) ?? session.command?.command ?? ""
        session.command = AgentCommandRun(command: command, output: output, failed: failed)
        session.showsCommand = true
    }

    private static func finish(_ session: inout AgentHubSession, event: AgentHookEvent, now: Date) -> AgentHubEffect? {
        let duration = session.turnStartedAt.map { max(now.timeIntervalSince($0), 0) } ?? 0
        session.phase = .finished
        session.question = nil
        session.turnStartedAt = nil
        if let message = event.message, !message.isEmpty {
            session.lastMessage = message
        }
        return .finished(sessionID: session.id, duration: duration)
    }

    private static func isRateLimit(_ message: String?) -> Bool {
        guard let message = message?.lowercased() else { return false }
        return message.contains("rate limit") || message.contains("usage limit")
    }
}
