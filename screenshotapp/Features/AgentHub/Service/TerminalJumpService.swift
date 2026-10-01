import AppKit

@MainActor
protocol TerminalJumping {
    /// Brings forward the terminal (tab) an agent session runs in.
    func jump(to context: AgentTerminalContext, cwd: String)
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

        if program == "apple_terminal" || context.bundleID == "com.apple.Terminal" {
            if !context.tty.isEmpty {
                runScript(Self.terminalScript, arguments: [context.tty], fallbackBundleID: "com.apple.Terminal")
                return
            }
            activate(bundleID: "com.apple.Terminal")
        } else if program == "iterm.app" || context.bundleID == "com.googlecode.iterm2" {
            // ITERM_SESSION_ID is "w0t0p0:<unique id>"; AppleScript knows the unique id.
            if let sessionID = context.itermSessionID.split(separator: ":").last, !sessionID.isEmpty {
                runScript(Self.itermScript, arguments: [String(sessionID)], fallbackBundleID: "com.googlecode.iterm2")
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
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source] + arguments
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice

            let found: Bool
            do {
                try process.run()
                process.waitUntilExit()
                let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                found = process.terminationStatus == 0 && text.contains("found")
            } catch {
                found = false
            }

            if !found {
                await MainActor.run { [weak self] in
                    self?.activate(bundleID: fallbackBundleID)
                }
            }
        }
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
}
