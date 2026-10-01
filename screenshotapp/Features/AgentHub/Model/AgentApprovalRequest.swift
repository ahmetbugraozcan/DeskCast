import Foundation

/// A Claude Code permission request waiting for the user's answer in the
/// island. The relay keeps Claude Code's hook call open until it's answered.
nonisolated struct AgentApprovalRequest: Identifiable, Equatable, Sendable {
    let id: UUID
    let sessionID: String
    let tool: String
    /// The command, file or pattern the tool wants to use.
    let detail: String?
    let permissionSuggestions: Data?
    let receivedAt: Date

    init(event: AgentHookEvent, id: UUID = UUID(), receivedAt: Date = Date()) {
        self.id = id
        sessionID = event.sessionID
        tool = event.toolName ?? "Tool"
        detail = event.toolSummary
        permissionSuggestions = event.permissionSuggestions
        self.receivedAt = receivedAt
    }

    var canAlwaysAllow: Bool {
        !allowSuggestions.isEmpty
    }

    /// The suggested rules that allow, which "Always allow" hands back to
    /// Claude Code to save.
    var allowSuggestions: [Any] {
        guard let permissionSuggestions,
              let suggestions = (try? JSONSerialization.jsonObject(with: permissionSuggestions)) as? [Any] else {
            return []
        }

        return suggestions.filter { suggestion in
            guard let suggestion = suggestion as? [String: Any] else { return false }
            return (suggestion["behavior"] as? String).map { $0 == "allow" } ?? true
        }
    }
}

/// The user's answer to a permission request.
nonisolated enum AgentApprovalDecision: String, Sendable {
    case allow
    case alwaysAllow
    case deny

    /// The JSON line the relay prints for Claude Code (PermissionRequest
    /// decision control).
    func hookOutput(for request: AgentApprovalRequest) -> String {
        var decision: [String: Any]
        switch self {
        case .allow:
            decision = ["behavior": "allow"]
        case .alwaysAllow:
            decision = ["behavior": "allow"]
            let suggestions = request.allowSuggestions
            if !suggestions.isEmpty {
                decision["updatedPermissions"] = suggestions
            }
        case .deny:
            decision = ["behavior": "deny", "message": "Denied from DeskCast"]
        }

        let output: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": decision
            ]
        ]
        let data = (try? JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])) ?? Data()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
