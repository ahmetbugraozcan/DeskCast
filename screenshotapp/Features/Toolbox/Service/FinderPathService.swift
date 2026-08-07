import Foundation

protocol FinderPathProviding {
    func frontFinderWindowPath() throws -> String
}

struct FinderPathService: FinderPathProviding {
    enum FinderPathError: LocalizedError {
        case scriptCreationFailed
        case scriptFailed(String)
        case noOpenFinderWindow
        case noFolderPath
        case automationDenied

        var errorDescription: String? {
            switch self {
            case .scriptCreationFailed:
                AppLocalization.string("Could not prepare Finder request.")
            case .scriptFailed(let message):
                message
            case .noOpenFinderWindow:
                AppLocalization.string("No Finder window is open.")
            case .noFolderPath:
                AppLocalization.string("This Finder window has no folder path (e.g. Recents or Search).")
            case .automationDenied:
                AppLocalization.string("Finder access is not allowed.")
            }
        }
    }

    private enum Sentinel {
        static let noWindow = "::NO_WINDOW::"
        static let noPath = "::NO_PATH::"
    }

    func frontFinderWindowPath() throws -> String {
        // Return sentinels for the "no window" / "no filesystem path" cases (the
        // latter covers smart folders like Recents, Search and Tags) so they can
        // be surfaced as clear messages instead of a raw AppleScript failure.
        let scriptSource = """
        tell application "Finder"
            if not (exists front Finder window) then
                return "\(Sentinel.noWindow)"
            end if

            try
                return POSIX path of (target of front Finder window as alias)
            on error
                return "\(Sentinel.noPath)"
            end try
        end tell
        """

        guard let script = NSAppleScript(source: scriptSource) else {
            throw FinderPathError.scriptCreationFailed
        }

        var errorInfo: NSDictionary?
        let output = script.executeAndReturnError(&errorInfo)

        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String
                ?? FinderPathError.scriptCreationFailed.localizedDescription
            let errorNumber = errorInfo[NSAppleScript.errorNumber] as? Int

            if errorNumber == -1743
                || message.localizedCaseInsensitiveContains("not authorized")
                || message.localizedCaseInsensitiveContains("not allowed") {
                throw FinderPathError.automationDenied
            }

            throw FinderPathError.scriptFailed(message)
        }

        let path = output.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        switch path {
        case Sentinel.noWindow, "":
            throw FinderPathError.noOpenFinderWindow
        case Sentinel.noPath:
            throw FinderPathError.noFolderPath
        default:
            return path
        }
    }
}
