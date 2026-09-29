import Foundation

/// A local coding agent whose transcripts DeskCast follows.
nonisolated enum AgentKind: String, CaseIterable, Sendable {
    case claude
    case codex

    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    var systemImage: String {
        switch self {
        case .claude: "asterisk"
        case .codex: "circle.hexagongrid.fill"
        }
    }
}

/// An agent turn in progress: the user sent a prompt and the agent hasn't
/// answered it yet.
nonisolated struct AgentSession: Equatable, Identifiable, Sendable {
    /// The transcript's path.
    let id: String
    let kind: AgentKind
    /// The working directory's name, when the transcript names one.
    let project: String?
    let startedAt: Date
}

/// What the closed island can show besides idle content. Listed in the
/// automatic order.
enum IslandActivity: String, CaseIterable, Identifiable {
    case media
    case agent
    case timer

    var id: String { rawValue }

    var panel: IslandPanel {
        switch self {
        case .media: .nowPlaying
        case .agent: .aiAgents
        case .timer: .timer
        }
    }
}

/// Follows one agent transcript line by line and tells when a turn starts
/// and ends. Claude Code writes `user`/`assistant` entries (a turn ends with
/// an assistant `end_turn`); Codex writes `task_started`/`task_complete`
/// events.
nonisolated struct AgentTranscriptState: Equatable, Sendable {
    enum Transition: Equatable, Sendable {
        case started
        case finished(duration: TimeInterval)
        case interrupted
    }

    let kind: AgentKind
    private(set) var isWorking = false
    private(set) var turnStartedAt: Date?
    private(set) var project: String?
    /// A Codex sub-thread (spawned by another thread), shown through its parent.
    private(set) var isSubthread = false

    /// Longer lines are tool output (files, images); they never change state.
    static let maxParsedLineLength = 256 * 1024

    private static let finalStopReasons: Set<String> = ["end_turn", "stop_sequence", "max_tokens", "refusal"]

    init(kind: AgentKind) {
        self.kind = kind
    }

    mutating func consume(_ line: Data, now: Date = Date()) -> Transition? {
        guard !line.isEmpty,
              line.count <= Self.maxParsedLineLength,
              let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else {
            return nil
        }

        let date = (object["timestamp"] as? String).flatMap(Self.date(from:)) ?? now

        switch kind {
        case .claude: return consumeClaude(object, date: date)
        case .codex: return consumeCodex(object, date: date)
        }
    }

    private mutating func consumeClaude(_ object: [String: Any], date: Date) -> Transition? {
        guard object["isSidechain"] as? Bool != true else { return nil }

        if let cwd = object["cwd"] as? String {
            project = Self.projectName(cwd)
        }

        guard let type = object["type"] as? String, let message = object["message"] as? [String: Any] else {
            return nil
        }

        switch type {
        case "user":
            guard object["isMeta"] as? Bool != true, object["isCompactSummary"] as? Bool != true else { return nil }

            guard let text = Self.promptText(message["content"]) else {
                // A tool result: the turn goes on.
                return isWorking ? nil : begin(at: date)
            }

            if text.hasPrefix("[Request interrupted") {
                return end(at: date, interrupted: true)
            }

            // Slash commands (`/model`, …) get no assistant reply.
            if text.hasPrefix("<command-") || text.hasPrefix("<local-command") {
                return nil
            }

            return isWorking ? nil : begin(at: date)
        case "assistant":
            if let stopReason = message["stop_reason"] as? String, Self.finalStopReasons.contains(stopReason) {
                return end(at: date, interrupted: false)
            }

            return isWorking ? nil : begin(at: date)
        default:
            return nil
        }
    }

    private mutating func consumeCodex(_ object: [String: Any], date: Date) -> Transition? {
        guard let type = object["type"] as? String, let payload = object["payload"] as? [String: Any] else {
            return nil
        }

        switch type {
        case "session_meta":
            if payload["parent_thread_id"] is String {
                isSubthread = true
            }
            if let cwd = payload["cwd"] as? String {
                project = Self.projectName(cwd)
            }
            return nil
        case "turn_context":
            if let cwd = payload["cwd"] as? String {
                project = Self.projectName(cwd)
            }
            return nil
        case "event_msg":
            switch payload["type"] as? String {
            case "task_started": return isWorking ? nil : begin(at: date)
            case "task_complete": return end(at: date, interrupted: false)
            case "turn_aborted": return end(at: date, interrupted: true)
            default: return nil
            }
        default:
            return nil
        }
    }

    private mutating func begin(at date: Date) -> Transition {
        isWorking = true
        turnStartedAt = date
        return .started
    }

    private mutating func end(at date: Date, interrupted: Bool) -> Transition? {
        guard isWorking else { return nil }
        isWorking = false
        let duration = turnStartedAt.map { max(date.timeIntervalSince($0), 0) } ?? 0
        turnStartedAt = nil
        return interrupted ? .interrupted : .finished(duration: duration)
    }

    /// The typed prompt of a user entry; `nil` for tool results.
    private static func promptText(_ content: Any?) -> String? {
        if let text = content as? String {
            return text
        }

        guard let blocks = content as? [[String: Any]] else { return nil }

        if blocks.contains(where: { $0["type"] as? String == "tool_result" }) {
            return nil
        }

        return blocks.first { $0["type"] as? String == "text" }?["text"] as? String ?? ""
    }

    private static func projectName(_ path: String) -> String? {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty || name == "/" ? nil : name
    }

    private static func date(from string: String) -> Date? {
        (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(string))
            ?? (try? Date.ISO8601FormatStyle().parse(string))
    }
}
