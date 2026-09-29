import AppKit
import Intents
import OSLog

enum FocusAccess: Equatable {
    case notDetermined
    case allowed
    case denied
}

/// Whether a Focus is on. macOS only tells apps on/off (never which Focus),
/// after the user allows Focus Status access; there is no change
/// notification, so callers poll.
@MainActor
protocol FocusStatusProviding: AnyObject {
    var access: FocusAccess { get }
    /// false while access isn't allowed.
    var isFocused: Bool { get }
    func requestAccess(_ completion: @escaping (FocusAccess) -> Void)
}

/// `INFocusStatusCenter`; needs the Communication Notifications entitlement
/// (Developer ID provisioning profile) and `NSFocusStatusUsageDescription`.
@MainActor
final class SystemFocusStatusService: FocusStatusProviding {
    var access: FocusAccess {
        Self.access(for: INFocusStatusCenter.default.authorizationStatus)
    }

    var isFocused: Bool {
        let status = INFocusStatusCenter.default.authorizationStatus
        let raw = INFocusStatusCenter.default.focusStatus.isFocused
        let summary = "auth=\(status.rawValue) focused=\(String(describing: raw))"
        if summary != lastLogged {
            lastLogged = summary
            Self.logger.notice("Focus status \(summary, privacy: .public)")
        }
        return Self.access(for: status) == .allowed && raw == true
    }

    private var lastLogged = ""
    private static let logger = Logger(subsystem: "com.ahmetbugraozcan.screenshotapp", category: "FocusStatus")

    func requestAccess(_ completion: @escaping (FocusAccess) -> Void) {
        INFocusStatusCenter.default.requestAuthorization { status in
            Task { @MainActor in
                completion(Self.access(for: status))
            }
        }
    }

    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Focus") {
            NSWorkspace.shared.open(url)
        }
    }

    private static func access(for status: INFocusStatusAuthorizationStatus) -> FocusAccess {
        switch status {
        case .authorized: .allowed
        case .denied, .restricted: .denied
        default: .notDetermined
        }
    }
}
