import Foundation

/// Composition root: owns the app's long-lived view models and wires their
/// dependencies in one place, so nothing reaches for a global singleton.
@MainActor
final class AppEnvironment {
    let dropShelf: DropShelfViewModel
    let screenshotShelf: ScreenshotShelfViewModel

    // Retained for the app's lifetime; the view models reference them weakly.
    private let dropShelfCoordinator: DropShelfPanelCoordinator
    private let screenshotShelfCoordinator: ScreenshotShelfPanelCoordinator

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
            settings: settings,
            toastPresenter: toastPresenter,
            screenRecording: ScreenRecordingPermissionService()
        )

        self.dropShelf = dropShelf
        self.screenshotShelf = screenshotShelf

        // Wire presentation coordinators and hand them to the view models.
        dropShelfCoordinator = DropShelfPanelCoordinator(store: dropShelf)
        screenshotShelfCoordinator = ScreenshotShelfPanelCoordinator(store: screenshotShelf)
        dropShelf.presenter = dropShelfCoordinator
        screenshotShelf.presenter = screenshotShelfCoordinator
    }
}
