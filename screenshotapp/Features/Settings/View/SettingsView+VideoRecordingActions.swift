import AppKit
import KeyboardShortcuts
import SwiftUI

extension SettingsView {
    func chooseVideoSaveDirectory() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: videoSaveDirectoryPath, isDirectory: true)
        panel.prompt = AppLocalization.string("Choose")

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        videoSaveDirectoryPath = url.path
    }

    func resetVideoRecordingSettings() {
        ScreenRecordingSettings.resetToDefaults()
        ToolboxSettings.resetTools([.captureVideo])
        KeyboardShortcuts.reset(.captureVideo)
    }
}
