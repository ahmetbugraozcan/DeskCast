import AppKit
import Combine
import Foundation

/// Composition root: owns the app's long-lived view models and wires their
/// dependencies in one place, so nothing reaches for a global singleton.
@MainActor
final class AppEnvironment: ObservableObject {
    let dropShelf: DropShelfViewModel
    let screenRecorder: ScreenRecordingViewModel
    let screenshotShelf: ScreenshotShelfViewModel
    let dynamicIsland: DynamicIslandViewModel
    let appUpdate: AppUpdateService

    // Retained for the app's lifetime; the view models reference them weakly.
    private let dropShelfCoordinator: DropShelfPanelCoordinator
    private let screenRecordingCoordinator: ScreenRecordingPanelCoordinator
    private let screenshotShelfCoordinator: ScreenshotShelfPanelCoordinator
    private let dynamicIslandCoordinator: DynamicIslandPanelCoordinator

    let settings: SettingsProviding

    init(settings: SettingsProviding = SettingsRepository()) {
        self.settings = settings
        settings.registerDefaults()

        let toastPresenter = ToastPresenter()
        let folderPicker = FolderPicker()

        let dropShelf = DropShelfViewModel(
            exporter: DropShelfExportService(),
            settings: settings,
            toastPresenter: toastPresenter,
            folderPicker: folderPicker
        )
        let screenshotShelf = ScreenshotShelfViewModel(
            shelfCollector: dropShelf,
            capturer: ScreenshotCaptureService(),
            recognizer: OCRTextRecognitionService(),
            exporter: ScreenshotExportService(),
            finderPath: FinderPathService(),
            videoMetadata: VideoMetadataService(),
            settings: settings,
            toastPresenter: toastPresenter,
            screenRecording: ScreenRecordingPermissionService()
        )
        let screenRecorder = ScreenRecordingViewModel(
            recorder: ScreenCaptureRecordingService(),
            sources: ScreenRecordingSourceService(),
            shelf: screenshotShelf,
            settings: settings,
            toastPresenter: toastPresenter,
            screenRecording: ScreenRecordingPermissionService()
        )

        let islandTimer = IslandTimerViewModel()
        let dynamicIsland = DynamicIslandViewModel(
            nowPlayingService: MediaPlayerNowPlayingService(),
            batteryMonitor: BatteryMonitorService(),
            systemNotifications: SystemNotificationMonitorService(),
            timer: islandTimer,
            settings: settings
        )
        // Island panels trigger other tools; each action closes the island first
        // so it doesn't cover the capture overlay or the opened window.
        let islandActions = IslandToolActions(
            captureArea: { [weak dynamicIsland, weak screenshotShelf] in
                dynamicIsland?.collapse()
                screenshotShelf?.captureSelectedArea()
            },
            captureVideo: { [weak dynamicIsland, weak screenRecorder] in
                dynamicIsland?.collapse()
                screenRecorder?.captureSelectedAreaVideo()
            },
            captureText: { [weak dynamicIsland, weak screenshotShelf] in
                dynamicIsland?.collapse()
                screenshotShelf?.captureOCRTextFromSelectedArea()
            },
            copyFinderPath: { [weak screenshotShelf] in
                screenshotShelf?.copyFrontFinderPath()
            },
            toggleDropShelf: { [weak dropShelf] in
                dropShelf?.toggleShelf()
            },
            openSettings: { [weak dynamicIsland] in
                dynamicIsland?.collapse()
                Self.openSettingsWindow()
            }
        )
        let islandPanels = IslandPanelModels(
            timer: islandTimer,
            screenshots: screenshotShelf,
            dropShelf: dropShelf,
            actions: islandActions
        )

        self.dropShelf = dropShelf
        self.screenRecorder = screenRecorder
        self.screenshotShelf = screenshotShelf
        self.dynamicIsland = dynamicIsland
        appUpdate = AppUpdateService()

        // Wire presentation coordinators and hand them to the view models.
        dropShelfCoordinator = DropShelfPanelCoordinator(store: dropShelf)
        screenRecordingCoordinator = ScreenRecordingPanelCoordinator(store: screenRecorder)
        screenshotShelfCoordinator = ScreenshotShelfPanelCoordinator(store: screenshotShelf)
        dynamicIslandCoordinator = DynamicIslandPanelCoordinator(store: dynamicIsland, panels: islandPanels)
        dropShelf.presenter = dropShelfCoordinator
        screenRecorder.presenter = screenRecordingCoordinator
        screenshotShelf.presenter = screenshotShelfCoordinator
        dynamicIsland.presenter = dynamicIslandCoordinator

        // Route DeskCast's own toasts into the island while it is showing.
        toastPresenter.islandRouter = dynamicIsland
        // The island panel is shown immediately (unlike the on-demand shelves),
        // so defer it to the next main-actor turn, after launch has finished.
        Task { @MainActor in
            dynamicIsland.start()
        }
    }

    /// Opens the SwiftUI `Settings` scene from AppKit code. SwiftUI only exposes
    /// `openSettings` inside views, so trigger the app menu's "Settings…" item
    /// (⌘,) that the scene installs.
    static func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)

        let settingsItem = NSApp.mainMenu?.items.first?.submenu?.items.first { item in
            item.keyEquivalent == "," && item.keyEquivalentModifierMask == .command
        }

        if let settingsItem, let action = settingsItem.action {
            NSApp.sendAction(action, to: settingsItem.target, from: settingsItem)
        } else {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }
}
