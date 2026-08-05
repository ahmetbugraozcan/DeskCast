import Foundation

/// Single seam for reading and mutating persisted settings. View models depend on
/// this instead of poking the `*Settings` static namespaces (which remain the
/// schema: keys, defaults, clamping, and the immutable `*Snapshot` read models).
protocol SettingsProviding {
    func registerDefaults()

    func screenshotShelfSettings() -> ScreenshotShelfSettingsSnapshot
    func dropShelfSettings() -> DropShelfSettingsSnapshot

    func isToolEnabled(_ tool: ToolboxToolID) -> Bool

    func resetScreenshotShelf()
    func resetDropShelf()
    func resetTools(_ tools: [ToolboxToolID])
}

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

    func resetScreenshotShelf() {
        ScreenshotShelfSettings.resetToDefaults(in: defaults)
    }

    func resetDropShelf() {
        DropShelfSettings.resetToDefaults(in: defaults)
    }

    func resetTools(_ tools: [ToolboxToolID]) {
        ToolboxSettings.resetTools(tools, in: defaults)
    }
}
