import AppKit
import IOKit.pwr_mgt

/// Quick system toggles for the Controls panel. Each uses a public mechanism:
/// appearance via System Events scripting (asks for Automation once), "keep
/// awake" via an IOKit power assertion, display sleep via `pmset`.
@MainActor
final class SystemControlsService {
    private var keepAwakeAssertion: IOPMAssertionID?

    var isDarkMode: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    func toggleDarkMode(completion: @escaping @MainActor () -> Void) {
        let source = """
        tell application id "com.apple.systemevents"
            tell appearance preferences to set dark mode to not dark mode
        end tell
        """

        DispatchQueue.global(qos: .userInitiated).async {
            var errorInfo: NSDictionary?
            _ = NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)

            Task { @MainActor in
                completion()
            }
        }
    }

    var isKeepingAwake: Bool {
        keepAwakeAssertion != nil
    }

    func setKeepAwake(_ enabled: Bool) {
        if enabled {
            guard keepAwakeAssertion == nil else { return }

            var assertionID = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "DeskCast keep awake" as CFString,
                &assertionID
            )

            if result == kIOReturnSuccess {
                keepAwakeAssertion = assertionID
            }
        } else if let keepAwakeAssertion {
            IOPMAssertionRelease(keepAwakeAssertion)
            self.keepAwakeAssertion = nil
        }
    }

    func sleepDisplay() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["displaysleepnow"]
        try? process.run()
    }

    func startScreenSaver() {
        let url = URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func openSystemSettings() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
