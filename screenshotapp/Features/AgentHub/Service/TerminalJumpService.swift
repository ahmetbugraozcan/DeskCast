import AppKit

@MainActor
protocol TerminalJumping {
    /// Brings forward the terminal (tab) an agent session runs in.
    func jump(to context: AgentTerminalContext, cwd: String)
    /// Whether text can be typed into the session's terminal tab.
    func canSendText(to context: AgentTerminalContext) -> Bool
    /// Types `text` and Return into the session's tab without bringing it
    /// forward (Terminal and iTerm2 only). False when the tab wasn't found.
    func sendText(_ text: String, to context: AgentTerminalContext) async -> Bool
}

/// Terminal → tab by tty, iTerm2 → session by id (AppleScript, asks for
/// Automation once); VS Code / Cursor → the session's folder; any other app
/// is just activated.
final class TerminalJumpService: TerminalJumping {
    private static let editors: [String: String] = [
        "vscode": "com.microsoft.VSCode",
        "cursor": "com.todesktop.230313mzl4w4u92"
    ]

    func jump(to context: AgentTerminalContext, cwd: String) {
        let program = context.termProgram.lowercased()

        if Self.isTerminal(context) {
            if !context.tty.isEmpty {
                runScript(Self.terminalScript, arguments: [context.tty], fallbackBundleID: "com.apple.Terminal")
                return
            }
            activate(bundleID: "com.apple.Terminal")
        } else if Self.isITerm(context) {
            if let sessionID = Self.itermUniqueID(context) {
                runScript(Self.itermScript, arguments: [sessionID], fallbackBundleID: "com.googlecode.iterm2")
                return
            }
            activate(bundleID: "com.googlecode.iterm2")
        } else if program == "vscode" {
            openFolder(cwd, bundleID: context.bundleID.isEmpty ? Self.editors["vscode"] ?? "" : context.bundleID)
        } else if !context.bundleID.isEmpty {
            activate(bundleID: context.bundleID)
        } else if let bundleID = Self.bundleID(forTermProgram: program) {
            activate(bundleID: bundleID)
        } else {
            // No terminal in the environment: the Claude app (or an IDE) runs it.
            activate(bundleID: "com.anthropic.claudefordesktop")
        }
    }

    func canSendText(to context: AgentTerminalContext) -> Bool {
        if Self.isTerminal(context) { return !context.tty.isEmpty }
        if Self.isITerm(context) { return Self.itermUniqueID(context) != nil }
        return false
    }

    func sendText(_ text: String, to context: AgentTerminalContext) async -> Bool {
        // A newline would submit each line separately.
        let line = text.components(separatedBy: .newlines).joined(separator: " ")
        if Self.isTerminal(context), !context.tty.isEmpty {
            return await Self.runOSAScript(Self.terminalSendScript, arguments: [context.tty, line])
        }
        if Self.isITerm(context), let sessionID = Self.itermUniqueID(context) {
            return await Self.runOSAScript(Self.itermSendScript, arguments: [sessionID, line])
        }
        return false
    }

    private static func isTerminal(_ context: AgentTerminalContext) -> Bool {
        context.termProgram.lowercased() == "apple_terminal" || context.bundleID == "com.apple.Terminal"
    }

    private static func isITerm(_ context: AgentTerminalContext) -> Bool {
        context.termProgram.lowercased() == "iterm.app" || context.bundleID == "com.googlecode.iterm2"
    }

    /// ITERM_SESSION_ID is "w0t0p0:<unique id>"; AppleScript knows the unique id.
    private static func itermUniqueID(_ context: AgentTerminalContext) -> String? {
        guard let id = context.itermSessionID.split(separator: ":").last, !id.isEmpty else { return nil }
        return String(id)
    }

    private static func bundleID(forTermProgram program: String) -> String? {
        switch program {
        case "ghostty": "com.mitchellh.ghostty"
        case "warpterminal": "dev.warp.Warp-Stable"
        case "wezterm": "com.github.wez.wezterm"
        case "kitty": "net.kovidgoyal.kitty"
        case "alacritty": "org.alacritty"
        case "tabby": "org.tabby"
        case "hyper": "co.zeit.hyper"
        default: nil
        }
    }

    private func activate(bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func openFolder(_ path: String, bundleID: String) {
        guard !path.isEmpty, let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            activate(bundleID: bundleID)
            return
        }
        NSWorkspace.shared.open(
            [URL(fileURLWithPath: path, isDirectory: true)],
            withApplicationAt: app,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    /// Runs `osascript` off the main thread; when the script finds nothing
    /// (or isn't allowed), the app is at least brought forward.
    private func runScript(_ source: String, arguments: [String], fallbackBundleID: String) {
        Task {
            if await !Self.runOSAScript(source, arguments: arguments) {
                activate(bundleID: fallbackBundleID)
            }
        }
    }

    /// True when the script ran and printed "found".
    private static func runOSAScript(_ source: String, arguments: [String]) async -> Bool {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source] + arguments
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                return process.terminationStatus == 0 && text.contains("found")
            } catch {
                return false
            }
        }.value
    }

    private static let terminalScript = """
    on run argv
        set wanted to item 1 of argv
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is wanted then
                        set selected of t to true
                        set index of w to 1
                        activate
                        return "found"
                    end if
                end repeat
            end repeat
        end tell
        return "missing"
    end run
    """

    private static let itermScript = """
    on run argv
        set wanted to item 1 of argv
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if unique id of s is wanted then
                            select w
                            select t
                            select s
                            activate
                            return "found"
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return "missing"
    end run
    """

    /// `do script` in a tab types the text followed by Return into whatever
    /// runs there (Claude Code's prompt), without selecting the tab.
    private static let terminalSendScript = """
    on run argv
        set wanted to item 1 of argv
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is wanted then
                        do script (item 2 of argv) in t
                        return "found"
                    end if
                end repeat
            end repeat
        end tell
        return "missing"
    end run
    """

    private static let itermSendScript = """
    on run argv
        set wanted to item 1 of argv
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if unique id of s is wanted then
                            tell s to write text (item 2 of argv)
                            return "found"
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return "missing"
    end run
    """
}
