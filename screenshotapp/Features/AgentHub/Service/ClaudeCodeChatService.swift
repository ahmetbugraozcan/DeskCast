import Foundation

@MainActor
protocol ClaudeCodeAsking: AnyObject {
    /// The installed `claude` command, if any.
    var executablePath: String? { get }
    /// Asks Claude Code; `sessionID` continues that conversation.
    func ask(prompt: String, sessionID: String?, extraFolders: [String]) async throws -> ClaudeCodeReply
    /// Where a picture of an attached window is saved for Claude Code to read.
    func saveWindowImage(_ data: Data) -> String?
}

/// Runs the user's own Claude Code (`claude -p`) in a DeskCast folder, so
/// the Ask page works with their Claude plan and sign-in. Claude Code only
/// gets read-only tools (Read, WebSearch, WebFetch) and none of the user's
/// settings, hooks or MCP servers.
final class ClaudeCodeChatService: ClaudeCodeAsking {
    private static let timeout: TimeInterval = 300

    private let fileManager = FileManager.default

    var executablePath: String? {
        let home = fileManager.homeDirectoryForCurrentUser.path
        return ClaudeCodeChatProtocol.candidatePaths(home: home).first { fileManager.isExecutableFile(atPath: $0) }
    }

    private var workingFolder: URL? {
        guard let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let folder = support
            .appendingPathComponent("DeskCast", isDirectory: true)
            .appendingPathComponent(ClaudeCodeChatProtocol.workingFolderName, isDirectory: true)
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func saveWindowImage(_ data: Data) -> String? {
        guard let folder = workingFolder else { return nil }
        // Only the latest window is kept.
        if let old = try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            for file in old where file.lastPathComponent.hasPrefix("window-") {
                try? fileManager.removeItem(at: file)
            }
        }
        let url = folder.appendingPathComponent("window-\(UUID().uuidString.prefix(8)).jpg")
        return (try? data.write(to: url, options: .atomic)) == nil ? nil : url.path
    }

    func ask(prompt: String, sessionID: String?, extraFolders: [String]) async throws -> ClaudeCodeReply {
        guard let executable = executablePath else {
            throw ClaudeChatError.api(AppLocalization.string("agentHub.ask.error.noClaudeCode"))
        }
        guard let folder = workingFolder else {
            throw ClaudeChatError.api(AppLocalization.string("agentHub.ask.error.claudeCode"))
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ClaudeCodeChatProtocol.arguments(prompt: prompt, resume: sessionID, extraFolders: extraFolders)
        process.currentDirectoryURL = folder
        var environment = ProcessInfo.processInfo.environment
        let executableFolder = URL(fileURLWithPath: executable).deletingLastPathComponent().path
        environment["PATH"] = [executableFolder, "/opt/homebrew/bin", "/usr/local/bin", environment["PATH"] ?? "/usr/bin:/bin"]
            .joined(separator: ":")
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let output = Pipe()
        process.standardOutput = output

        let timeout = Self.timeout
        let data: Data = try await withTaskCancellationHandler {
            try await Task.detached {
                try process.run()
                let timer = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                timer.cancel()
                return data
            }.value
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }

        try Task.checkCancellation()
        return try ClaudeCodeChatProtocol.parseReply(data)
    }
}
