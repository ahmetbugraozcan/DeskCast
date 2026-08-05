import AppKit
import CoreGraphics

@MainActor
protocol ScreenRecordingChecking {
    var hasAccess: Bool { get }
    func ensureAccess() -> Bool
    func openSettings()
}

@MainActor
struct ScreenRecordingPermissionService: ScreenRecordingChecking {
    var hasAccess: Bool {
        CGPreflightScreenCaptureAccess()
    }

    func ensureAccess() -> Bool {
        if hasAccess {
            return true
        }

        return CGRequestScreenCaptureAccess()
    }

    func openSettings() {
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
