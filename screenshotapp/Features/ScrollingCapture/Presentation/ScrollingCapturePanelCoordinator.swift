import AppKit
import SwiftUI

private final class ScrollingCaptureKeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Owns the scrolling capture's windows: the area picker, the outline around
/// the captured area, and the floating controls.
@MainActor
final class ScrollingCapturePanelCoordinator: ScrollingCapturePresenting {
    private let store: ScrollingCaptureViewModel
    private var selectionPanel: NSPanel?
    private var outlinePanel: NSPanel?
    private var controlsPanel: NSPanel?

    private static let outlineInset: CGFloat = 3
    private static let controlsGap: CGFloat = 12

    init(store: ScrollingCaptureViewModel) {
        self.store = store
    }

    func selectArea(completion: @escaping (ScrollingCaptureArea?) -> Void) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main,
              let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            completion(nil)
            return
        }

        let panel = ScrollingCaptureKeyPanel(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hasShadow = false
        panel.isOpaque = false
        panel.level = .screenSaver
        panel.contentView = NSHostingView(
            rootView: ScreenAreaSelectionView(
                initialRect: nil,
                title: AppLocalization.string("scrollCapture.select.title"),
                message: AppLocalization.string("scrollCapture.select.message"),
                onComplete: { [weak self] rect in
                    self?.selectionPanel?.orderOut(nil)
                    self?.selectionPanel = nil
                    // Hand focus back so the app being captured is the active one.
                    NSApp.deactivate()
                    completion(rect.map {
                        ScrollingCaptureArea(
                            displayID: displayID, displayFrame: screen.frame, scale: screen.backingScaleFactor, rect: $0
                        )
                    })
                }
            )
        )
        selectionPanel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func showCaptureControls(for area: ScrollingCaptureArea) {
        hideCaptureControls()

        // Display-local, top-left rect → global, bottom-left Cocoa frame.
        let frame = CGRect(
            x: area.displayFrame.minX + area.rect.minX,
            y: area.displayFrame.maxY - area.rect.maxY,
            width: area.rect.width,
            height: area.rect.height
        )

        let outline = makePanel(
            frame: frame.insetBy(dx: -Self.outlineInset, dy: -Self.outlineInset),
            content: NSHostingView(rootView: ScrollingCaptureOutlineView())
        )
        outline.ignoresMouseEvents = true
        outline.orderFrontRegardless()
        outlinePanel = outline

        let hostingView = NSHostingView(rootView: ScrollingCaptureControlsView(model: store))
        let size = hostingView.fittingSize
        let controls = makePanel(frame: CGRect(origin: .zero, size: size), content: hostingView)
        controls.setFrameOrigin(Self.controlsOrigin(size: size, around: frame, in: area.displayFrame))
        controls.orderFrontRegardless()
        controlsPanel = controls
    }

    func hideCaptureControls() {
        outlinePanel?.orderOut(nil)
        controlsPanel?.orderOut(nil)
        outlinePanel = nil
        controlsPanel = nil
    }

    /// Below the area when there's room, else above it, else inside its bottom edge.
    static func controlsOrigin(size: CGSize, around frame: CGRect, in screen: CGRect) -> CGPoint {
        let originX = min(max(frame.midX - size.width / 2, screen.minX + 8), screen.maxX - size.width - 8)
        let below = frame.minY - controlsGap - size.height
        if below >= screen.minY + 8 { return CGPoint(x: originX, y: below) }
        let above = frame.maxY + controlsGap
        if above + size.height <= screen.maxY - 8 { return CGPoint(x: originX, y: above) }
        return CGPoint(x: originX, y: frame.minY + controlsGap)
    }

    private func makePanel(frame: CGRect, content: NSView) -> NSPanel {
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.contentView = content
        return panel
    }
}
