import Foundation

@MainActor
protocol MailSending {
    /// Sends `file` with Apple Mail. Only ever called from the Send button.
    func send(file: URL, to recipient: String, subject: String, message: String) async throws
}

/// Sends a dropped file through Mail with AppleScript (asks for Automation
/// → Mail the first time). The arguments are passed to the script as
/// `argv`, never pasted into its source.
final class MailSendService: MailSending {
    enum MailError: LocalizedError {
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .failed(let reason): AppLocalization.formatted("agentHub.mail.error", reason)
            }
        }
    }

    private static let script = """
    on run argv
        set theRecipient to item 1 of argv
        set theSubject to item 2 of argv
        set theBody to item 3 of argv
        set theFile to POSIX file (item 4 of argv)
        tell application "Mail"
            set msg to make new outgoing message with properties {subject:theSubject, content:theBody & return & return, visible:false}
            tell msg
                make new to recipient at end of to recipients with properties {address:theRecipient}
                make new attachment with properties {file name:theFile} at after the last paragraph of content
            end tell
            delay 1
            send msg
        end tell
        return "sent"
    end run
    """

    nonisolated static func isValidAddress(_ address: String) -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: "@")
        return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".") && !trimmed.contains(" ")
            && !parts[1].hasPrefix(".") && !parts[1].hasSuffix(".")
    }

    func send(file: URL, to recipient: String, subject: String, message: String) async throws {
        let arguments = ["-e", Self.script, recipient, subject, message, file.path]
        let result: (status: Int32, error: String) = await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = arguments
            let errors = Pipe()
            process.standardError = errors
            process.standardOutput = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return (-1, "osascript") }
            process.waitUntilExit()
            let text = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return (process.terminationStatus, text.trimmingCharacters(in: .whitespacesAndNewlines))
        }.value

        guard result.status == 0 else {
            throw MailError.failed(result.error.isEmpty ? "Mail" : result.error)
        }
    }
}
