import AppKit

/// A choice for where the screenshot shelf appears. `id` is either a sentinel
/// (`pointer`/`primary`) or a specific display's stable CGDisplay UUID string.
struct ScreenshotShelfDisplayOption: Identifiable, Hashable {
    let id: String
    let name: String
}

enum ScreenshotShelfDisplayCatalog {
    static let pointerID = "pointer"
    static let primaryID = "primary"

    /// Stable per-display identifier that survives reconnects (unlike the raw
    /// `CGDirectDisplayID`, which can change).
    static func displayUUID(for screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        let displayID = CGDirectDisplayID(number.uint32Value)
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return nil
        }
        return CFUUIDCreateString(nil, uuid) as String
    }

    /// Options for the settings picker: the two automatic modes followed by each
    /// connected display by name.
    static func options() -> [ScreenshotShelfDisplayOption] {
        var options = [
            ScreenshotShelfDisplayOption(
                id: pointerID,
                name: AppLocalization.string("Automatic (display with pointer)")
            ),
            ScreenshotShelfDisplayOption(
                id: primaryID,
                name: AppLocalization.string("Primary display")
            )
        ]

        for screen in NSScreen.screens {
            guard let uuid = displayUUID(for: screen) else { continue }
            options.append(ScreenshotShelfDisplayOption(id: uuid, name: screen.localizedName))
        }

        return options
    }

    /// Resolves an explicit selection to a screen. Returns nil for `pointer`
    /// (the caller uses the cursor location) or when a chosen display is gone.
    static func screen(for mode: String) -> NSScreen? {
        switch mode {
        case pointerID:
            return nil
        case primaryID:
            return NSScreen.screens.first
        default:
            return NSScreen.screens.first { displayUUID(for: $0) == mode }
        }
    }
}
