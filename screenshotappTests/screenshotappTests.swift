import Foundation
import Testing
@testable import screenshotapp

struct DeskCastSettingsTests {

    @Test func screenshotSettingsRegisterAutoSaveDefaults() throws {
        let suiteName = "ScreenshotShelfSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        ScreenshotShelfSettings.registerDefaults(in: defaults)
        let snapshot = ScreenshotShelfSettings.snapshot(from: defaults)

        #expect(snapshot.autoSaveCapturedScreenshots)
        #expect(snapshot.saveDirectoryPath == ScreenshotShelfSettings.defaultSaveDirectoryPath)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func screenshotSettingsResetRestoresDefaults() throws {
        let suiteName = "ScreenshotShelfSettingsResetTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        ScreenshotShelfSettings.registerDefaults(in: defaults)
        defaults.set(999, forKey: ScreenshotShelfSettings.Keys.maxStackCount)
        defaults.set(false, forKey: ScreenshotShelfSettings.Keys.autoSaveCapturedScreenshots)
        defaults.set("Custom", forKey: ScreenshotShelfSettings.Keys.exportFilenamePrefix)

        ScreenshotShelfSettings.resetToDefaults(in: defaults)
        let snapshot = ScreenshotShelfSettings.snapshot(from: defaults)

        #expect(snapshot.maxStackCount == ScreenshotShelfSettings.defaultMaxStackCount)
        #expect(snapshot.autoSaveCapturedScreenshots == ScreenshotShelfSettings.defaultAutoSaveCapturedScreenshots)
        #expect(
            defaults.string(forKey: ScreenshotShelfSettings.Keys.exportFilenamePrefix)
                == ScreenshotShelfSettings.defaultExportFilenamePrefix
        )

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func toolboxResetToolsRestoresOnlyRequestedToolDefaults() throws {
        let suiteName = "ToolboxSettingsResetTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        ToolboxSettings.registerDefaults(in: defaults)
        defaults.set(false, forKey: ToolboxToolID.captureSelectedArea.enabledKey)
        defaults.set(false, forKey: ToolboxToolID.captureSelectedArea.showInMenuKey)
        defaults.set(false, forKey: ToolboxToolID.copyFinderPath.enabledKey)
        defaults.set(false, forKey: ToolboxToolID.copyFinderPath.showInMenuKey)
        defaults.set(false, forKey: ToolboxToolID.dropShelf.enabledKey)
        defaults.set(false, forKey: ToolboxToolID.dropShelf.showInMenuKey)

        ToolboxSettings.resetTools([.captureSelectedArea], in: defaults)

        #expect(defaults.bool(forKey: ToolboxToolID.captureSelectedArea.enabledKey) == ToolboxToolID.captureSelectedArea.defaultEnabled)
        #expect(
            defaults.bool(forKey: ToolboxToolID.captureSelectedArea.showInMenuKey)
                == ToolboxToolID.captureSelectedArea.defaultShowInMenu
        )
        #expect(defaults.bool(forKey: ToolboxToolID.copyFinderPath.enabledKey) == false)
        #expect(defaults.bool(forKey: ToolboxToolID.copyFinderPath.showInMenuKey) == false)
        #expect(defaults.bool(forKey: ToolboxToolID.dropShelf.enabledKey) == false)
        #expect(defaults.bool(forKey: ToolboxToolID.dropShelf.showInMenuKey) == false)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func dropShelfSettingsRegisterDefaultsAndClampInvalidValues() throws {
        let suiteName = "DropShelfSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        DropShelfSettings.registerDefaults(in: defaults)
        defaults.set(999, forKey: DropShelfSettings.Keys.maxItemCount)
        defaults.set(1_000, forKey: DropShelfSettings.Keys.customItemWidth)
        defaults.set(0, forKey: DropShelfSettings.Keys.shakeSensitivity)
        defaults.set("invalid", forKey: DropShelfSettings.Keys.layoutMode)
        let snapshot = DropShelfSettings.snapshot(from: defaults)

        #expect(snapshot.layoutMode == DropShelfSettings.defaultLayoutMode)
        #expect(snapshot.maxItemCount == DropShelfSettings.maxItemCountRange.upperBound)
        #expect(snapshot.customItemWidth == DropShelfSettings.customItemWidthRange.upperBound)
        #expect(snapshot.shakeSensitivity == DropShelfSettings.shakeSensitivityRange.lowerBound)
        #expect(snapshot.openOnShake == DropShelfSettings.defaultOpenOnShake)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func dropShelfSettingsResetRestoresDefaults() throws {
        let suiteName = "DropShelfSettingsResetTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        DropShelfSettings.registerDefaults(in: defaults)
        defaults.set(StackDirection.vertical.rawValue, forKey: DropShelfSettings.Keys.stackDirection)
        defaults.set(DropShelfLayoutMode.grid.rawValue, forKey: DropShelfSettings.Keys.layoutMode)
        defaults.set(false, forKey: DropShelfSettings.Keys.openOnShake)
        defaults.set(2, forKey: DropShelfSettings.Keys.shakeSensitivity)

        DropShelfSettings.resetToDefaults(in: defaults)
        let snapshot = DropShelfSettings.snapshot(from: defaults)

        #expect(snapshot.stackDirection == DropShelfSettings.defaultStackDirection)
        #expect(snapshot.layoutMode == DropShelfSettings.defaultLayoutMode)
        #expect(snapshot.openOnShake == DropShelfSettings.defaultOpenOnShake)
        #expect(snapshot.shakeSensitivity == DropShelfSettings.defaultShakeSensitivity)

        defaults.removePersistentDomain(forName: suiteName)
    }

}
