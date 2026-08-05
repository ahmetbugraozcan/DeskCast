import Foundation
import ServiceManagement

/// Wraps `SMAppService.mainApp` so the app can register/unregister itself as a
/// macOS login item (Settings → General → Login Items) without a separate helper.
enum LaunchAtLoginService {
    /// Whether the app is currently registered to launch at login.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// The user may have toggled the app off in System Settings; surface that so
    /// the UI can point them there instead of silently failing.
    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// Registers or unregisters the login item. Throws if the OS rejects the change.
    static func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp

        if enabled {
            guard service.status != .enabled else { return }
            try service.register()
        } else {
            guard service.status != .notRegistered else { return }
            try service.unregister()
        }
    }
}
