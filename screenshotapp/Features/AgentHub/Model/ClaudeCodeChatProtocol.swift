import Foundation

/// How the Ask page reaches Claude.
nonisolated enum AgentAskBackend: String, CaseIterable, Sendable {
    /// The Anthropic API with the user's own key.
    case api
    /// The `claude` command the user installed (Claude Code), with its own
    /// sign-in — so a Pro/Max plan works without an API key.
    case claudeCode
}

/// The answer of one `claude -p --output-format json` run.
nonisolated struct ClaudeCodeReply: Equatable, Sendable {
    let text: String
    let sessionID: String?
}

/// Builds `claude -p` arguments and reads its JSON result. Pure.
nonisolated enum ClaudeCodeChatProtocol {
    /// Reading files and the web only: nothing that edits files or runs
    /// commands, and nothing that asks for permission.
    static let tools = "Read,WebSearch,WebFetch"

    /// The folder DeskCast runs `claude` in. Claude Code keeps these
    /// conversations under `~/.claude/projects/<folder name>`, which the
    /// agent activity watcher skips.
    static let workingFolderName = "DeskCast-Ask"

    static let systemPrompt = """
    You are Bip, the assistant in DeskCast, a Mac menu bar app; your answers show in a small panel \
    around the Mac's notch. You can read files and search the web, but never change anything. Answer in \
    the user's language. Keep answers short and direct: a few sentences or a short list, as plain text \
    with line breaks. No Markdown headings, tables, bold or code fences. When the question is about an \
    attached window or file, read it first and answer about it.
    """

    /// Usual install places; a Mac app doesn't get the user's shell `PATH`.
    static func candidatePaths(home: String) -> [String] {
        [
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude"
        ]
    }

    /// `resume` is the session of the conversation so far, if any.
    static func arguments(prompt: String, resume sessionID: String?, extraFolders: [String]) -> [String] {
        var arguments = [
            "-p", prompt,
            "--output-format", "json",
            "--tools", tools,
            "--allowedTools", tools,
            "--permission-mode", "dontAsk",
            // The user's settings would run their hooks (DeskCast's own too).
            "--setting-sources", "project",
            "--strict-mcp-config",
            "--append-system-prompt", systemPrompt
        ]
        if let sessionID {
            arguments += ["--resume", sessionID]
        }
        for folder in extraFolders {
            arguments += ["--add-dir", folder]
        }
        return arguments
    }

    /// The question with what it is about. `windowImagePath` is the saved
    /// picture of an attached window.
    static func prompt(question: String, attachment: AgentChatAttachment?, windowImagePath: String?) -> String {
        switch attachment {
        case .file(let url):
            return "Attached file: \(url.path)\n\n\(question)"
        case .window(let context):
            var text = "Attached window — app: \(context.appName), title: \(context.title)"
            if let url = context.url {
                text += ", URL: \(url)"
            }
            if let windowImagePath {
                text += "\nScreenshot of the window: \(windowImagePath)"
            }
            return "\(text)\n\n\(question)"
        case nil:
            return question
        }
    }

    /// The `result` of a run, or the error it reports.
    static func parseReply(_ data: Data) throws -> ClaudeCodeReply {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              object["type"] as? String == "result" else {
            let output = (String(bytes: data.prefix(400), encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            throw ClaudeChatError.api(output.isEmpty ? AppLocalization.string("agentHub.ask.error.claudeCode") : output)
        }

        let text = (object["result"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if object["is_error"] as? Bool == true {
            if text.localizedCaseInsensitiveContains("not logged in") || text.contains("/login") {
                throw ClaudeChatError.api(AppLocalization.string("agentHub.ask.error.claudeLogin"))
            }
            throw ClaudeChatError.api(text.isEmpty ? AppLocalization.string("agentHub.ask.error.claudeCode") : text)
        }
        return ClaudeCodeReply(text: text, sessionID: object["session_id"] as? String)
    }

    /// Claude Code's transcript folder for DeskCast's own Ask conversations.
    static func isAskTranscript(_ path: String) -> Bool {
        path.contains("-\(workingFolderName)/")
    }
}
