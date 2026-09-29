import AppKit
import SwiftUI

/// Owns the open Trim / GIF windows, one per shelf video.
@MainActor
final class VideoEditorWindows {
    private let trimmer: VideoTrimming
    private let gifExporter: GIFExporting
    private var controllers: [UUID: VideoEditorWindowController] = [:]

    init(trimmer: VideoTrimming = VideoTrimService(), gifExporter: GIFExporting = GIFExportService()) {
        self.trimmer = trimmer
        self.gifExporter = gifExporter
    }

    func open(_ source: URL, itemID: UUID, handlers: VideoEditorResultHandlers) {
        NSApp.activate(ignoringOtherApps: true)

        if let existing = controllers[itemID] {
            existing.show()
            return
        }

        let model = VideoEditorViewModel(source: source, trimmer: trimmer, gifExporter: gifExporter, handlers: handlers)
        let controller = VideoEditorWindowController(model: model)
        controller.onClose = { [weak self] in
            self?.controllers[itemID] = nil
        }
        controllers[itemID] = controller
        controller.show()
    }
}

@MainActor
private final class VideoEditorWindowController: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?

    private let window: NSWindow
    private let model: VideoEditorViewModel

    init(model: VideoEditorViewModel) {
        self.model = model
        window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 900, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()

        window.title = AppLocalization.formatted("videoEdit.title", model.source.lastPathComponent)
        window.isReleasedWhenClosed = false
        window.minSize = CGSize(width: 820, height: 460)
        window.delegate = self
        window.contentView = NSHostingView(
            rootView: VideoEditorView(model: model, cancel: { [weak self] in self?.window.close() })
                .environment(\.locale, AppLocalization.currentLanguage.locale)
        )
        model.onFinished = { [weak self] in self?.window.close() }
        window.center()
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model.stop()
        onClose?()
    }
}
