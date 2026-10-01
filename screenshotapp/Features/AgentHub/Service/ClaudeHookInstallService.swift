import Foundation

/// A change to Claude Code's settings file, shown to the user before it's written.
nonisolated struct ClaudeHookChange: Equatable, Sendable {
    let original: String
    let updated: String
    /// Lines only in the new file ("+ …") or only in the old one ("- …").
    let diff: [String]
}

@MainActor
protocol ClaudeHookInstalling: AnyObject {
    func isInstalled() -> Bool
    func installedApprovalTimeout() -> Int?
    func previewInstall(approvalTimeout: Int) throws -> ClaudeHookChange
    func previewUninstall() throws -> ClaudeHookChange
    /// Backs up the settings file, then writes `change.updated`.
    func apply(_ change: ClaudeHookChange) throws
}

/// Reads and writes `~/.claude/settings.json`. Every write is preceded by a
/// dated backup next to it; other tools' hooks are left as they are.
final class ClaudeHookInstallService: ClaudeHookInstalling {
    enum InstallError: LocalizedError {
        case unreadableSettings
        case changedSincePreview

        var errorDescription: String? {
            switch self {
            case .unreadableSettings: AppLocalization.string("agentHub.hooks.error.unreadable")
            case .changedSincePreview: AppLocalization.string("agentHub.hooks.error.changed")
            }
        }
    }

    private let settingsURL: URL

    init(settingsURL: URL = AgentHookPaths.claudeSettings) {
        self.settingsURL = settingsURL
    }

    func isInstalled() -> Bool {
        (try? readSettings()).map { ClaudeHookConfiguration.isInstalled(in: $0.object) } ?? false
    }

    func installedApprovalTimeout() -> Int? {
        (try? readSettings()).flatMap { ClaudeHookConfiguration.installedApprovalTimeout(in: $0.object) }
    }

    func previewInstall(approvalTimeout: Int) throws -> ClaudeHookChange {
        let current = try readSettings()
        let updated = ClaudeHookConfiguration.installing(
            into: current.object,
            scriptPath: AgentHookPaths.relayScript.path,
            approvalTimeout: approvalTimeout
        )
        return try change(from: current.text, to: updated)
    }

    func previewUninstall() throws -> ClaudeHookChange {
        let current = try readSettings()
        return try change(from: current.text, to: ClaudeHookConfiguration.removing(from: current.object))
    }

    func apply(_ change: ClaudeHookChange) throws {
        // The user approved a diff against this exact file.
        guard try readSettings().text == change.original else {
            throw InstallError.changedSincePreview
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: settingsURL.path) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let backup = settingsURL.deletingLastPathComponent()
                .appendingPathComponent("settings.json.bak-\(formatter.string(from: Date()))")
            try fileManager.copyItem(at: settingsURL, to: backup)
        }

        try Data(change.updated.utf8).write(to: settingsURL, options: .atomic)
    }

    private func readSettings() throws -> (text: String, object: [String: Any]) {
        guard let data = try? Data(contentsOf: settingsURL), !data.isEmpty else {
            return ("", [:])
        }
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let text = String(data: data, encoding: .utf8) else {
            throw InstallError.unreadableSettings
        }
        return (text, object)
    }

    private func change(from original: String, to object: [String: Any]) throws -> ClaudeHookChange {
        let data = try JSONSerialization.data(withJSONObject: object, options: Self.printOptions)
        let updated = (String(data: data, encoding: .utf8) ?? "") + "\n"
        return ClaudeHookChange(original: original, updated: updated, diff: Self.lineDiff(from: original, to: updated))
    }

    /// A line diff that ignores formatting-only changes: the old file is
    /// re-printed the same way before comparing.
    nonisolated private static let printOptions: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

    nonisolated static func lineDiff(from original: String, to updated: String) -> [String] {
        let normalized: String
        if let data = original.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data),
           let printed = try? JSONSerialization.data(withJSONObject: object, options: printOptions) {
            normalized = String(data: printed, encoding: .utf8) ?? original
        } else {
            normalized = original
        }

        let old = normalized.components(separatedBy: .newlines)
        let new = updated.components(separatedBy: .newlines)
        let difference = new.difference(from: old)

        var lines: [String] = []
        for change in difference.removals {
            if case .remove(_, let line, _) = change, !line.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.append("- " + line)
            }
        }
        for change in difference.insertions {
            if case .insert(_, let line, _) = change, !line.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.append("+ " + line)
            }
        }
        return lines
    }
}
