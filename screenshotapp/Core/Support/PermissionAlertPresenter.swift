import AppKit

@MainActor
enum PermissionAlertPresenter {
    static func showScreenRecordingHelp(openSettings: () -> Void) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = AppLocalization.string("Screen Recording Permission Required")
        alert.informativeText = AppLocalization.formatted(
            "Enable %@ in System Settings > Privacy & Security > Screen & System Audio Recording, then quit and reopen %@.",
            AppConstants.displayName,
            AppConstants.displayName
        )
        alert.addButton(withTitle: AppLocalization.string("Open Settings"))
        alert.addButton(withTitle: AppLocalization.string("Cancel"))

        if alert.runModal() == .alertFirstButtonReturn {
            openSettings()
        }
    }
}
