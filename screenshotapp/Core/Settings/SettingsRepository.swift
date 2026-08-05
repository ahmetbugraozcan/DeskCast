import Foundation

// Narrow, per-concern reading protocols so each client depends only on what it
// uses (ISP). The `*Settings` static namespaces remain the schema (keys,
// defaults, clamping, and the immutable `*Snapshot` read models).

protocol SettingsRegistering {
    func registerDefaults()
}

protocol ScreenshotShelfSettingsReading {
    func screenshotShelfSettings() -> ScreenshotShelfSettingsSnapshot
}

protocol DropShelfSettingsReading {
    func dropShelfSettings() -> DropShelfSettingsSnapshot
}

protocol ToolboxSettingsReading {
    func isToolEnabled(_ tool: ToolboxToolID) -> Bool
}

/// Umbrella used by the composition root; conformers satisfy every reader.
protocol SettingsProviding: SettingsRegistering,
    ScreenshotShelfSettingsReading,
    DropShelfSettingsReading,
    ToolboxSettingsReading {}

struct SettingsRepository: SettingsProviding {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func registerDefaults() {
        ScreenshotShelfSettings.registerDefaults(in: defaults)
        DropShelfSettings.registerDefaults(in: defaults)
        ToolboxSettings.registerDefaults(in: defaults)
    }

    func screenshotShelfSettings() -> ScreenshotShelfSettingsSnapshot {
        ScreenshotShelfSettings.snapshot(from: defaults)
    }

    func dropShelfSettings() -> DropShelfSettingsSnapshot {
        DropShelfSettings.snapshot(from: defaults)
    }

    func isToolEnabled(_ tool: ToolboxToolID) -> Bool {
        ToolboxSettings.isEnabled(tool, defaults: defaults)
    }
}
