import AppKit
import Intents

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
        access == .allowed && INFocusStatusCenter.default.focusStatus.isFocused == true
    }

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
