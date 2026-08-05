import Foundation

enum FinderPathService {
    enum FinderPathError: LocalizedError {
        case scriptCreationFailed
        case scriptFailed(String)
        case noOpenFinderWindow
        case automationDenied

        var errorDescription: String? {
            switch self {
            case .scriptCreationFailed:
                AppLocalization.string("Could not prepare Finder request.")
            case .scriptFailed(let message):
                message
            case .noOpenFinderWindow:
                AppLocalization.string("No Finder window is open.")
            case .automationDenied:
                AppLocalization.string("Finder access is not allowed.")
            }
        }
    }

    static func frontFinderWindowPath() throws -> String {
        let scriptSource = """
        tell application "Finder"
            if not (exists front Finder window) then
                error "No Finder window is open."
            end if

            try
                return POSIX path of (target of front Finder window as alias)
            on error
                return POSIX path of (insertion location as alias)
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

            if message.localizedCaseInsensitiveContains("No Finder window") {
                throw FinderPathError.noOpenFinderWindow
            }

            if errorNumber == -1743
                || message.localizedCaseInsensitiveContains("not authorized")
                || message.localizedCaseInsensitiveContains("not allowed") {
                throw FinderPathError.automationDenied
            }

            throw FinderPathError.scriptFailed(message)
        }

        guard let path = output.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            throw FinderPathError.noOpenFinderWindow
        }

        return path
    }
}
