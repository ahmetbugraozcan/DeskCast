import Foundation

/// Adds DeskCast's relay to the `hooks` of Claude Code's `settings.json`, or
/// takes it out again, without touching anyone else's hooks. Pure: works on
/// the decoded JSON object.
nonisolated enum ClaudeHookConfiguration {
    /// Every hook DeskCast installs runs a command containing this.
    static let marker = "deskcast-hook"

    /// Hook events DeskCast listens to, with their timeout in seconds.
    static func events(approvalTimeout: Int) -> [(name: String, timeout: Int)] {
        [
            ("SessionStart", 10),
            ("SessionEnd", 10),
            ("UserPromptSubmit", 10),
            ("PreToolUse", 10),
            ("PostToolUse", 10),
            ("PostToolUseFailure", 10),
            ("PermissionRequest", approvalTimeout + 10),
            ("Notification", 10),
            ("Stop", 10),
            ("StopFailure", 10),
            ("SubagentStart", 10),
            ("SubagentStop", 10)
        ]
    }

    static func command(scriptPath: String) -> String {
        "\"" + scriptPath.replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// `settings` with DeskCast's hooks (re)added; earlier DeskCast entries
    /// are replaced so the timeouts and path stay current.
    static func installing(into settings: [String: Any], scriptPath: String, approvalTimeout: Int) -> [String: Any] {
        var settings = removing(from: settings)
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        let command = command(scriptPath: scriptPath)

        for event in events(approvalTimeout: approvalTimeout) {
            var matchers = hooks[event.name] as? [[String: Any]] ?? []
            matchers.append([
                "hooks": [["type": "command", "command": command, "timeout": event.timeout]]
            ])
            hooks[event.name] = matchers
        }

        settings["hooks"] = hooks
        return settings
    }

    /// `settings` without any DeskCast hook. Other hooks in a shared matcher
    /// stay; matchers and events left empty are removed.
    static func removing(from settings: [String: Any]) -> [String: Any] {
        guard var hooks = settings["hooks"] as? [String: Any] else { return settings }
        var settings = settings

        for (event, value) in hooks {
            guard let matchers = value as? [[String: Any]] else { continue }

            let cleaned: [[String: Any]] = matchers.compactMap { matcher in
                guard let commands = matcher["hooks"] as? [[String: Any]] else { return matcher }
                let kept = commands.filter { !isDeskCastHook($0) }
                guard kept.count != commands.count else { return matcher }
                guard !kept.isEmpty else { return nil }
                var matcher = matcher
                matcher["hooks"] = kept
                return matcher
            }

            hooks[event] = cleaned.isEmpty ? nil : cleaned
        }

        if hooks.isEmpty {
            settings.removeValue(forKey: "hooks")
        } else {
            settings["hooks"] = hooks
        }
        return settings
    }

    /// Whether every event DeskCast needs has its hook.
    static func isInstalled(in settings: [String: Any]) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }

        return events(approvalTimeout: 0).allSatisfy { event in
            (hooks[event.name] as? [[String: Any]] ?? []).contains { matcher in
                (matcher["hooks"] as? [[String: Any]] ?? []).contains(where: isDeskCastHook)
            }
        }
    }

    /// The PermissionRequest timeout DeskCast installed, if any.
    static func installedApprovalTimeout(in settings: [String: Any]) -> Int? {
        let matchers = (settings["hooks"] as? [String: Any])?["PermissionRequest"] as? [[String: Any]] ?? []
        for matcher in matchers {
            for hook in matcher["hooks"] as? [[String: Any]] ?? [] where isDeskCastHook(hook) {
                return hook["timeout"] as? Int
            }
        }
        return nil
    }

    private static func isDeskCastHook(_ hook: [String: Any]) -> Bool {
        (hook["command"] as? String)?.contains(marker) == true
    }
}
