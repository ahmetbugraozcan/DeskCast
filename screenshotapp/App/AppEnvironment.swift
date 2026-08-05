import Foundation

/// Composition root: owns the app's long-lived view models and wires their
/// dependencies in one place, so nothing reaches for a global singleton.
@MainActor
final class AppEnvironment {
    let dropShelf: DropShelfViewModel
    let screenshotShelf: ScreenshotShelfViewModel

    init() {
        ScreenshotShelfSettings.registerDefaults()
        DropShelfSettings.registerDefaults()
        ToolboxSettings.registerDefaults()

        let dropShelf = DropShelfViewModel(exporter: DropShelfExportService())
        self.dropShelf = dropShelf
        self.screenshotShelf = ScreenshotShelfViewModel(
            shelfCollector: dropShelf,
            capturer: ScreenshotCaptureService(),
            recognizer: OCRTextRecognitionService(),
            exporter: ScreenshotExportService(),
            finderPath: FinderPathService()
        )
    }
}
