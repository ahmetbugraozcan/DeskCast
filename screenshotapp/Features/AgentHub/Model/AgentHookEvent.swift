import Foundation

/// Where an agent session runs, as the hook relay saw it in its environment.
/// Used to bring the right terminal tab forward.
nonisolated struct AgentTerminalContext: Equatable, Sendable {
    var termProgram = ""
    var bundleID = ""
    var tty = ""
    var itermSessionID = ""
    var termSessionID = ""

    init(termProgram: String = "", bundleID: String = "", tty: String = "", itermSessionID: String = "", termSessionID: String = "") {
        self.termProgram = termProgram
        self.bundleID = bundleID
        self.tty = tty
        self.itermSessionID = itermSessionID
        self.termSessionID = termSessionID
    }

    init(payload: [String: Any]) {
        termProgram = payload["term_program"] as? String ?? ""
        bundleID = payload["bundle_id"] as? String ?? ""
        tty = payload["tty"] as? String ?? ""
        itermSessionID = payload["iterm_session_id"] as? String ?? ""
        termSessionID = payload["term_session_id"] as? String ?? ""
    }

    var isEmpty: Bool {
        termProgram.isEmpty && bundleID.isEmpty && tty.isEmpty
    }

    /// Keeps the fields this context knows and fills the rest from `other`.
    func merged(with other: AgentTerminalContext) -> AgentTerminalContext {
        AgentTerminalContext(
            termProgram: termProgram.isEmpty ? other.termProgram : termProgram,
            bundleID: bundleID.isEmpty ? other.bundleID : bundleID,
            tty: tty.isEmpty ? other.tty : tty,
            itermSessionID: itermSessionID.isEmpty ? other.itermSessionID : itermSessionID,
            termSessionID: termSessionID.isEmpty ? other.termSessionID : termSessionID
        )
    }
}

/// A question Claude asked with its question tool.
nonisolated struct AgentQuestion: Equatable, Sendable {
    var text: String
    var options: [String]
}

/// One Claude Code (or Codex) hook call, decoded from the JSON the relay
/// forwards. See https://code.claude.com/docs/en/hooks for the payloads;
/// Codex's match them (https://learn.chatgpt.com/docs/hooks).
nonisolated struct AgentHookEvent: Equatable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case sessionStart = "SessionStart"
        case sessionEnd = "SessionEnd"
        case userPromptSubmit = "UserPromptSubmit"
        case preToolUse = "PreToolUse"
        case postToolUse = "PostToolUse"
        case postToolUseFailure = "PostToolUseFailure"
        case permissionRequest = "PermissionRequest"
        case notification = "Notification"
        case stop = "Stop"
        case stopFailure = "StopFailure"
        case subagentStart = "SubagentStart"
        case subagentStop = "SubagentStop"
        /// Codex: the user stopped the turn.
        case interrupt = "Interrupt"
    }

    let kind: Kind
    let sessionID: String
    let cwd: String
    /// Another agent that reuses the relay (`--agent <name>`); `nil` for Claude Code.
    let agent: String?
    let terminal: AgentTerminalContext
    var toolName: String?
    /// The most telling part of the tool input: a command, a file, a pattern…
    var toolSummary: String?
    var prompt: String?
    var message: String?
    var notificationType: String?
    var errorType: String?
    var question: AgentQuestion?
    /// `permission_suggestions` re-encoded as JSON, sent back for "always allow".
    var permissionSuggestions: Data?
    /// The edit a file tool is about to make (PreToolUse, PermissionRequest).
    var codeChange: AgentCodeChange?
    /// The shell command (Bash), in full.
    var command: String?
    /// The end of a shell command's output (PostToolUse, PostToolUseFailure).
    var commandOutput: [String]?

    /// The question tool's name; its questions can't be answered by a hook,
    /// so DeskCast shows them and sends the user to the terminal.
    static let questionTool = "AskUserQuestion"

    init(
        kind: Kind,
        sessionID: String,
        cwd: String = "",
        agent: String? = nil,
        terminal: AgentTerminalContext = AgentTerminalContext()
    ) {
        self.kind = kind
        self.sessionID = sessionID
        self.cwd = cwd
        self.agent = agent
        self.terminal = terminal
    }

    init?(payload: [String: Any]) {
        guard let name = payload["hook_event_name"] as? String, let kind = Kind(rawValue: name) else {
            return nil
        }

        let sessionID = (payload["session_id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "unknown"
        self.init(
            kind: kind,
            sessionID: sessionID,
            cwd: payload["cwd"] as? String ?? "",
            agent: Self.validAgentName(payload["deskcast_agent"] as? String),
            terminal: AgentTerminalContext(payload: payload)
        )

        toolName = payload["tool_name"] as? String
        let input = payload["tool_input"] as? [String: Any] ?? [:]
        toolSummary = Self.summary(of: input)
        prompt = (payload["prompt"] as? String).map(Self.singleLine)
        message = (payload["last_assistant_message"] as? String ?? payload["message"] as? String ?? payload["error_message"] as? String)
            .map(Self.trimmed)
        notificationType = payload["notification_type"] as? String
        errorType = payload["error_type"] as? String

        if toolName == Self.questionTool {
            question = Self.question(from: input)
        }

        if let suggestions = payload["permission_suggestions"] as? [Any], !suggestions.isEmpty {
            permissionSuggestions = try? JSONSerialization.data(withJSONObject: suggestions)
        }

        guard let tool = toolName else { return }
        if tool == Self.shellTool {
            command = Self.command(from: input["command"])
            if kind == .postToolUse || kind == .postToolUseFailure {
                commandOutput = AgentCommandRun.outputLines(from: payload["tool_response"] ?? payload["error"])
            }
        }
        if kind == .preToolUse || kind == .permissionRequest {
            // The file as it is before the edit, to number the changed lines.
            let isEdit = tool == "Edit" || tool == "MultiEdit"
            let fileText = isEdit ? (input["file_path"] as? String).flatMap(Self.readSmallFile) : nil
            codeChange = AgentCodeChange.make(tool: tool, input: input, fileText: fileText)
        }
    }

    /// Claude Code's and Codex's shell tool.
    static let shellTool = "Bash"

    /// Codex may pass the command as an argument list.
    private static func command(from value: Any?) -> String? {
        if let text = value as? String {
            return text
        }
        if let parts = value as? [String] {
            // ["bash", "-lc", "npm test"] → "npm test"
            if parts.count == 3, parts[1] == "-lc" || parts[1] == "-c" {
                return parts[2]
            }
            return parts.joined(separator: " ")
        }
        return nil
    }

    private static func readSmallFile(_ path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 512_000,
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// A name other agents pass with `--agent`: lowercase letters, digits and
    /// hyphens, 1–24 characters. "claude" is reserved for Claude Code itself.
    static func validAgentName(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty, raw.count <= 24, raw != "claude" else { return nil }
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
        return raw.allSatisfy(allowed.contains) ? raw : nil
    }

    static func summary(of input: [String: Any]) -> String? {
        // Codex's apply_patch: the files the patch touches.
        for value in input.values {
            if let text = value as? String, let files = patchedFiles(text), !files.isEmpty {
                return files.joined(separator: ", ")
            }
        }

        for key in ["command", "file_path", "notebook_path", "path", "pattern", "query", "url", "description", "prompt"] {
            guard let value = input[key] as? String, !value.isEmpty else { continue }

            switch key {
            case "file_path", "notebook_path", "path":
                return URL(fileURLWithPath: value).lastPathComponent
            default:
                return singleLine(value)
            }
        }

        return nil
    }

    /// File names in a Codex patch ("*** Update File: path"), or `nil` when
    /// `text` isn't one.
    static func patchedFiles(_ text: String) -> [String]? {
        guard text.contains("*** Begin Patch") else { return nil }
        let prefixes = ["*** Update File: ", "*** Add File: ", "*** Delete File: "]
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            guard let prefix = prefixes.first(where: { line.hasPrefix($0) }) else { return nil }
            return URL(fileURLWithPath: String(line.dropFirst(prefix.count))).lastPathComponent
        }
    }

    private static func question(from input: [String: Any]) -> AgentQuestion? {
        guard let first = (input["questions"] as? [[String: Any]])?.first,
              let text = first["question"] as? String else {
            return nil
        }

        let options = (first["options"] as? [[String: Any]] ?? []).compactMap { $0["label"] as? String }
        return AgentQuestion(text: text, options: options)
    }

    static func singleLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Long messages are cut to what the island can show.
    private static func trimmed(_ text: String) -> String {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count > 600 ? String(text.prefix(600)) + "…" : text
    }
}
