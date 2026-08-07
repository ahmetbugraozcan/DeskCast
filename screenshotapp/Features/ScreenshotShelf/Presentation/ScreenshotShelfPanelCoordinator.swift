import AppKit
import CoreGraphics
import SwiftUI

struct ScreenshotShelfScreenAnchor: Equatable {
    let screenNumber: CGDirectDisplayID
}

/// Presentation boundary: the view model drives the floating shelf panel through
/// this protocol instead of owning AppKit directly.
@MainActor
protocol ScreenshotShelfPresenting: AnyObject {
    func screenAnchorForNewCapture(settings: ScreenshotShelfSettingsSnapshot) -> ScreenshotShelfScreenAnchor?
    func refresh(screenAnchor: ScreenshotShelfScreenAnchor?)
    func refreshIfVisible()
    func hide()
}

extension ScreenshotShelfPresenting {
    func refresh() {
        refresh(screenAnchor: nil)
    }
}

@MainActor
final class ScreenshotShelfPanelCoordinator: ScreenshotShelfPresenting {
    private let store: ScreenshotShelfViewModel
    private var panel: NSPanel?
    private var anchoredScreen: ScreenshotShelfScreenAnchor?

    private let screenMargin: CGFloat = 18

    init(store: ScreenshotShelfViewModel) {
        self.store = store
    }

    func screenAnchorForNewCapture(settings: ScreenshotShelfSettingsSnapshot) -> ScreenshotShelfScreenAnchor? {
        resolvedScreenForNewCapture(settings: settings).screenAnchor
    }

    func refresh(screenAnchor: ScreenshotShelfScreenAnchor? = nil) {
        guard !store.screenshots.isEmpty else {
            panel?.orderOut(nil)
            anchoredScreen = nil
            return
        }

        if let screenAnchor {
            anchoredScreen = screenAnchor
        }

        let panel = panel ?? makePanel()
        self.panel = panel
        updateFrame(for: panel)
        panel.orderFrontRegardless()
    }

    func refreshIfVisible() {
        guard panel?.isVisible == true else {
            return
        }

        refresh()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: CGSize(width: 160, height: 120)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.contentView = NSHostingView(rootView: ScreenshotShelfView(store: store))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isOpaque = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.backgroundColor = .clear

        return panel
    }

    private func updateFrame(for panel: NSPanel) {
        let settings = ScreenshotShelfSettings.snapshot()
        let thumbnailSize = settings.thumbnailDimensions
        // Cap the panel to `maxStackCount` cards; any extra items scroll inside the
        // shelf's ScrollView instead of growing the window (or being discarded).
        let visibleCount = min(store.screenshots.count, settings.maxStackCount)
        let count = CGFloat(visibleCount)
        let screen = screenForShelf(settings: settings, panel: panel)
        let visibleFrame = screen.visibleFrame
        let maxWidth = visibleFrame.width - screenMargin * 2
        let maxHeight = visibleFrame.height - screenMargin * 2
        let desiredSize = desiredPanelSize(
            count: count,
            thumbnailSize: thumbnailSize,
            stackDirection: settings.stackDirection
        )
        let size = CGSize(
            width: min(desiredSize.width, maxWidth),
            height: min(desiredSize.height, maxHeight)
        )
        let origin = origin(
            for: size,
            in: visibleFrame,
            position: settings.previewPosition
        )

        panel.setFrame(
            NSRect(origin: origin, size: size),
            display: true,
            animate: true
        )
    }

    private func desiredPanelSize(
        count: CGFloat,
        thumbnailSize: CGSize,
        stackDirection: StackDirection
    ) -> CGSize {
        let cardSize = ScreenshotShelfView.cardSize(for: thumbnailSize)

        switch stackDirection {
        case .horizontal:
            return CGSize(
                width: ScreenshotShelfView.outerPadding * 2
                    + cardSize.width * count
                    + ScreenshotShelfView.thumbnailSpacing * max(0, count - 1),
                height: ScreenshotShelfView.outerPadding * 2 + cardSize.height
            )
        case .vertical:
            return CGSize(
                width: ScreenshotShelfView.outerPadding * 2 + cardSize.width,
                height: ScreenshotShelfView.outerPadding * 2
                    + cardSize.height * count
                    + ScreenshotShelfView.thumbnailSpacing * max(0, count - 1)
            )
        }
    }

    private func origin(
        for size: CGSize,
        in visibleFrame: NSRect,
        position: PreviewPosition
    ) -> CGPoint {
        switch position {
        case .bottomLeft:
            CGPoint(x: visibleFrame.minX + screenMargin, y: visibleFrame.minY + screenMargin)
        case .bottomRight:
            CGPoint(x: visibleFrame.maxX - size.width - screenMargin, y: visibleFrame.minY + screenMargin)
        case .topLeft:
            CGPoint(x: visibleFrame.minX + screenMargin, y: visibleFrame.maxY - size.height - screenMargin)
        case .topRight:
            CGPoint(x: visibleFrame.maxX - size.width - screenMargin, y: visibleFrame.maxY - size.height - screenMargin)
        }
    }

    private func screenForShelf(settings: ScreenshotShelfSettingsSnapshot, panel: NSPanel) -> NSScreen {
        if let screen = screen(for: anchoredScreen) {
            return screen
        }

        if let screen = panel.screen {
            anchoredScreen = screen.screenAnchor
            return screen
        }

        let screen = resolvedScreenForNewCapture(settings: settings)
        anchoredScreen = screen.screenAnchor

        return screen
    }

    private func resolvedScreenForNewCapture(settings: ScreenshotShelfSettingsSnapshot) -> NSScreen {
        // "pointer" (and any stale/disconnected explicit choice) → the display the
        // user is currently on; "primary" or a specific display → that display.
        if settings.previewDisplayMode == ScreenshotShelfDisplayCatalog.pointerID {
            return screenForMouseLocation()
        }

        return ScreenshotShelfDisplayCatalog.screen(for: settings.previewDisplayMode)
            ?? screenForMouseLocation()
    }

    private func screen(for anchor: ScreenshotShelfScreenAnchor?) -> NSScreen? {
        guard let anchor else {
            return nil
        }

        return NSScreen.screens.first { screen in
            screen.screenAnchor == anchor
        }
    }

    private func screenForMouseLocation() -> NSScreen {
        NSScreen.screens.first { screen in
            screen.frame.contains(NSEvent.mouseLocation)
        } ?? NSScreen.main ?? NSScreen.screens[0]
    }

}

private extension NSScreen {
    var screenAnchor: ScreenshotShelfScreenAnchor? {
        guard let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }

        return ScreenshotShelfScreenAnchor(screenNumber: screenNumber.uint32Value)
    }
}
