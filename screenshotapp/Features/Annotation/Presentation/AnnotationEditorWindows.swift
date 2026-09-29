import AppKit
import SwiftUI

/// What the editor hands back: `done` replaces the capture, `copy` only copies.
struct AnnotationEditorResultHandlers {
    let done: (NSImage) -> Void
    let copy: (NSImage) -> Void
}

/// Owns the open annotation editor windows. Opening the same capture twice
/// brings its existing window forward instead of starting a second edit.
@MainActor
final class AnnotationEditorWindows {
    private var controllers: [UUID: AnnotationEditorWindowController] = [:]

    func open(_ image: NSImage, itemID: UUID, handlers: AnnotationEditorResultHandlers) {
        NSApp.activate(ignoringOtherApps: true)

        if let existing = controllers[itemID] {
            existing.show()
            return
        }

        let controller = AnnotationEditorWindowController(image: image, handlers: handlers)
        controller.onClose = { [weak self] in
            self?.controllers[itemID] = nil
        }
        controllers[itemID] = controller
        controller.show()
    }
}

@MainActor
private final class AnnotationEditorWindowController: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?

    private let window: NSWindow
    private let model: AnnotationEditorViewModel
    private let handlers: AnnotationEditorResultHandlers

    private static let minimumSize = CGSize(width: 900, height: 480)

    init(image: NSImage, handlers: AnnotationEditorResultHandlers) {
        model = AnnotationEditorViewModel(image: image, mosaic: AnnotationPixelation.mosaic(of: image))
        self.handlers = handlers
        window = NSWindow(
            contentRect: CGRect(origin: .zero, size: Self.initialSize(for: image.size)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()

        window.title = AppLocalization.string("annotate.title")
        window.isReleasedWhenClosed = false
        window.minSize = Self.minimumSize
        window.delegate = self
        window.contentView = NSHostingView(
            rootView: AnnotationEditorView(
                model: model,
                actions: AnnotationEditorActions(
                    cancel: { [weak self] in self?.window.close() },
                    copy: { [weak self] in self?.copy() },
                    done: { [weak self] in self?.finish() }
                )
            )
            .environment(\.locale, AppLocalization.currentLanguage.locale)
        )
        window.center()
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    private func copy() {
        guard let rendered = render() else { return }
        handlers.copy(rendered)
    }

    private func finish() {
        let annotations = model.finishedAnnotations()
        if !annotations.isEmpty, let rendered = render() {
            handlers.done(rendered)
        }
        window.close()
    }

    private func render() -> NSImage? {
        let rendered = AnnotationRenderer.render(
            image: model.image,
            mosaic: model.mosaic,
            annotations: model.finishedAnnotations()
        )
        if rendered == nil { NSSound.beep() }
        return rendered
    }

    /// Fits the image at 100 % when possible, never more than 85 % of the screen.
    private static func initialSize(for imageSize: CGSize) -> CGSize {
        let visible = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        let chrome = CGSize(width: 40, height: AnnotationEditorView.toolbarHeight + 60)
        return CGSize(
            width: min(max(imageSize.width + chrome.width, minimumSize.width), visible.width * 0.85),
            height: min(max(imageSize.height + chrome.height, minimumSize.height), visible.height * 0.85)
        )
    }
}
