import AppKit
import CoreGraphics

@MainActor
enum ScreenRecordingPermissionService {
    static var hasAccess: Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func ensureAccess() -> Bool {
        if hasAccess {
            return true
        }

        return CGRequestScreenCaptureAccess()
    }

    static func openSettings() {
        if let screenRecordingURL = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ), NSWorkspace.shared.open(screenRecordingURL) {
            return
        }

        if let privacyURL = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            NSWorkspace.shared.open(privacyURL)
        }
    }
}
