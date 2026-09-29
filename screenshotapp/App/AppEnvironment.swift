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
    let colorPicker: ColorPickerViewModel
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
            exporter: DropShelfExportService(), processor: DropShelfFileProcessingService(),
            settings: settings, toastPresenter: toastPresenter, folderPicker: folderPicker
        )
        let screenshotShelf = ScreenshotShelfViewModel(
            shelfCollector: dropShelf,
            capturer: ScreenshotCaptureService(),
            recognizer: OCRTextRecognitionService(),
            barcodeReader: VisionBarcodeReadingService(),
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
        let islandActions = Self.makeIslandActions(
            island: dynamicIsland,
            screenshotShelf: screenshotShelf,
            screenRecorder: screenRecorder,
            dropShelf: dropShelf
        )
        let islandPanels = IslandPanelModels(
            timer: islandTimer,
            screenshots: screenshotShelf,
            dropShelf: dropShelf,
            actions: islandActions
        )
        islandPanels.bind(to: dynamicIsland)

        self.dropShelf = dropShelf
        self.screenRecorder = screenRecorder
        self.screenshotShelf = screenshotShelf
        self.dynamicIsland = dynamicIsland
        colorPicker = ColorPickerViewModel(sampler: ScreenColorSamplingService(), settings: settings, toastPresenter: toastPresenter)
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
        Task { @MainActor [weak self] in
            dynamicIsland.start()
            await self?.openDemoWindowsIfRequested()
        }
    }

    private func openDemoWindowsIfRequested() async {
        await Self.openDemoSettingsIfRequested()
        #if DEBUG
        DemoMenuPanelWindow.showIfRequested(environment: self)
        await DebugWindowSnapshot.writeIfRequested()
        #endif
    }

    /// Debug builds only: `-DeskCastDemoSettings <section>` opens Settings on
    /// that page for screenshots.
    private static func openDemoSettingsIfRequested() async {
        #if DEBUG
        guard UserDefaults.standard.string(forKey: "DeskCastDemoSettings") != nil else { return }
        try? await Task.sleep(for: .seconds(1.5))
        openSettingsWindow()
        #endif
    }

    /// Island panels trigger other tools; each capture action closes the island
    /// first so it doesn't cover the capture overlay or the opened window.
    private static func makeIslandActions(
        island dynamicIsland: DynamicIslandViewModel,
        screenshotShelf: ScreenshotShelfViewModel,
        screenRecorder: ScreenRecordingViewModel,
        dropShelf: DropShelfViewModel
    ) -> IslandToolActions {
        IslandToolActions(
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
                openSettingsWindow()
            }
        )
    }

    /// Opens the SwiftUI `Settings` scene from AppKit code. SwiftUI only exposes
    /// `openSettings` inside views, so trigger the app menu's "Settings…" item
    /// that the scene installs. Its key equivalent follows the keyboard layout
    /// (⌘ö on a Turkish Q layout, not ⌘,), so also match the scene's own
    /// `menuAction:`, which no other item in the app menu uses.
    static func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)

        let appMenuItems = NSApp.mainMenu?.items.first?.submenu?.items ?? []
        let settingsItem = appMenuItems.first { item in
            item.keyEquivalent == "," && item.keyEquivalentModifierMask == .command
        } ?? appMenuItems.first { item in
            item.action.map(NSStringFromSelector) == "menuAction:"
        }

        if let settingsItem, let action = settingsItem.action {
            NSApp.sendAction(action, to: settingsItem.target, from: settingsItem)
        } else {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }
}
