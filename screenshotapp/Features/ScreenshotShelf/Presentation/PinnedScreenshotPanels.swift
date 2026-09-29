import AppKit
import Combine
import SwiftUI

/// Owns the screenshots pinned on screen: each one is an always-on-top
/// borderless panel that stays until the user closes it.
@MainActor
final class PinnedScreenshotPanels {
    private var controllers: [UUID: PinnedScreenshotWindowController] = [:]
    /// Offset between consecutive pins so they don't land exactly on top of each other.
    private let cascadeStep: CGFloat = 24

    func pin(_ image: NSImage, copyAction: @escaping () -> Void) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let screen else { return }

        let cascade = CGFloat(controllers.count % 8) * cascadeStep
        let controller = PinnedScreenshotWindowController(
            image: image,
            visibleFrame: screen.visibleFrame.offsetBy(dx: cascade, dy: -cascade),
            copyAction: copyAction
        )
        let id = UUID()
        controller.onClose = { [weak self] in
            self?.controllers[id] = nil
        }
        controllers[id] = controller
        controller.show()
    }
}

/// Scale and opacity of one pinned screenshot, shared by its window and view.
@MainActor
final class PinnedScreenshotState: ObservableObject {
    let imageSize: CGSize
    @Published var scale: CGFloat
    @Published var opacity: Double = 1

    init(imageSize: CGSize, scale: CGFloat) {
        self.imageSize = imageSize
        self.scale = scale
    }
}

/// Borderless panels can't become key by default; a pinned screenshot needs to
/// so Esc closes it and ⌘C copies it. It never activates DeskCast.
private final class PinnedScreenshotPanel: NSPanel {
    var onCancel: (() -> Void)?
    var onCopy: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        // Esc; nothing in the panel handles text input, so `cancelOperation` never fires.
        if event.keyCode == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command, event.charactersIgnoringModifiers == "c" {
            onCopy?()
            return true
        }
        if modifiers == .command, event.charactersIgnoringModifiers == "w" {
            onCancel?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
private final class PinnedScreenshotWindowController {
    var onClose: (() -> Void)?

    private let panel: PinnedScreenshotPanel
    private let state: PinnedScreenshotState
    private var observers: Set<AnyCancellable> = []

    init(image: NSImage, visibleFrame: CGRect, copyAction: @escaping () -> Void) {
        let scale = PinnedScreenshotLayout.initialScale(imageSize: image.size, visibleFrame: visibleFrame)
        let state = PinnedScreenshotState(imageSize: image.size, scale: scale)
        let size = PinnedScreenshotLayout.contentSize(imageSize: image.size, scale: scale)
        let panel = PinnedScreenshotPanel(
            contentRect: PinnedScreenshotLayout.centeredFrame(size: size, in: visibleFrame),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.panel = panel
        self.state = state

        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.onCancel = { [weak self] in self?.close() }
        panel.onCopy = copyAction
        panel.contentView = NSHostingView(
            rootView: PinnedScreenshotView(
                image: image,
                state: state,
                closeAction: { [weak self] in self?.close() },
                copyAction: copyAction
            )
        )

        state.$scale
            .dropFirst()
            .sink { [weak self] scale in self?.resize(to: scale) }
            .store(in: &observers)
        state.$opacity
            .sink { [weak panel] opacity in panel?.alphaValue = CGFloat(opacity) }
            .store(in: &observers)
    }

    func show() {
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    private func resize(to scale: CGFloat) {
        let size = PinnedScreenshotLayout.contentSize(imageSize: state.imageSize, scale: scale)
        panel.setFrame(PinnedScreenshotLayout.frame(resizing: panel.frame, to: size), display: true)
        panel.invalidateShadow()
    }

    private func close() {
        observers.removeAll()
        panel.orderOut(nil)
        onClose?()
    }
}
