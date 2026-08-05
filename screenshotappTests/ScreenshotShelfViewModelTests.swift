import AppKit
import Testing
@testable import screenshotapp

/// Fakes made possible by the Phase 2 service protocols + Phase 1 injection.
@MainActor
private final class FakeShelfCollector: ShelfCollecting {
    private(set) var added: [(image: NSImage, name: String)] = []

    func addScreenshot(_ image: NSImage, name: String) {
        added.append((image, name))
    }
}

private struct NoopCapturer: ScreenshotCapturing {
    func captureSelectedArea(
        preserveClipboard: Bool,
        completion: @escaping (Result<NSImage, ScreenshotCaptureError>) -> Void
    ) {}
}

private struct NoopRecognizer: TextRecognizing {
    func recognizeText(in image: NSImage) async throws -> String { "" }
    func recognizeText(in image: NSImage, completion: @escaping (Result<String, Error>) -> Void) {}
}

private struct NoopExporter: ScreenshotExporting {
    func save(_ image: NSImage, to directoryURL: URL, suggestedFilename: String) throws -> URL { directoryURL }
    func save(_ image: NSImage, suggestedFilename: String) throws -> URL? { nil }
}

private struct NoopFinderPath: FinderPathProviding {
    func frontFinderWindowPath() throws -> String { "/" }
}

@MainActor
private final class SpyToastPresenter: ToastPresenting {
    private(set) var messages: [String] = []
    func show(_ message: String, systemImage: String) { messages.append(message) }
}

@MainActor
struct ScreenshotShelfViewModelTests {

    private func makeViewModel(collector: FakeShelfCollector) -> ScreenshotShelfViewModel {
        ScreenshotShelfViewModel(
            shelfCollector: collector,
            capturer: NoopCapturer(),
            recognizer: NoopRecognizer(),
            exporter: NoopExporter(),
            finderPath: NoopFinderPath(),
            settings: SettingsRepository(),
            toastPresenter: SpyToastPresenter()
        )
    }

    @Test func addToShelfForwardsCaptureToInjectedCollector() {
        let collector = FakeShelfCollector()
        let viewModel = makeViewModel(collector: collector)
        let item = ScreenshotItem(image: NSImage(size: NSSize(width: 8, height: 8)), isPinned: false)

        viewModel.addToShelf(item)

        #expect(collector.added.count == 1)
        #expect(collector.added.first?.name.hasSuffix(".png") == true)
    }
}
