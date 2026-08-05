import AppKit
import SwiftUI

final class DropShelfPanelController {
    private let store: DropShelfViewModel
    private var panel: NSPanel?
    private var lastKnownOrigin: CGPoint?

    private let screenMargin: CGFloat = 18

    init(store: DropShelfViewModel) {
        self.store = store
    }

    func refresh() {
        guard store.isShelfVisible else {
            hide()
            return
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
        if let panel {
            lastKnownOrigin = panel.frame.origin
        }

        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: CGSize(width: 360, height: 220)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.contentView = DropShelfHostingView(
            rootView: DropShelfView(store: store),
            store: store
        )
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = true
        panel.isMovableByWindowBackground = false
        panel.isOpaque = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.backgroundColor = .clear

        return panel
    }

    private func updateFrame(for panel: NSPanel) {
        let settings = DropShelfSettings.snapshot()
        let desiredSize = desiredPanelSize(settings: settings)
        let screen = screenForPanel(panel) ?? screenForMouseLocation()
        let visibleFrame = screen.visibleFrame
        let size = CGSize(
            width: min(desiredSize.width, visibleFrame.width - screenMargin * 2),
            height: min(desiredSize.height, visibleFrame.height - screenMargin * 2)
        )
        let origin = clampedOrigin(
            preferredOrigin: preferredOrigin(for: panel, size: size),
            size: size,
            visibleFrame: visibleFrame
        )
        lastKnownOrigin = origin

        panel.setFrame(
            NSRect(origin: origin, size: size),
            display: true,
            animate: true
        )
    }

    private func desiredPanelSize(settings: DropShelfSettingsSnapshot) -> CGSize {
        let itemSize = settings.itemDimensions

        switch settings.layoutMode {
        case .stack:
            return CGSize(
                width: max(380, itemSize.width + DropShelfView.outerPadding * 2 + 120),
                height: max(280, itemSize.height + DropShelfView.outerPadding * 2 + DropShelfView.headerHeight + 84)
            )
        case .grid:
            let columnCount = DropShelfView.gridColumnCount
            let itemCount = max(store.items.count, 1)
            let rowCount = min(2, max(1, Int(ceil(Double(itemCount) / Double(columnCount)))))
            let contentWidth = CGFloat(columnCount) * itemSize.width
                + CGFloat(columnCount - 1) * DropShelfView.gridSpacing
            let contentHeight = CGFloat(rowCount) * itemSize.height
                + CGFloat(max(rowCount - 1, 0)) * DropShelfView.gridSpacing

            return CGSize(
                width: max(420, contentWidth + DropShelfView.outerPadding * 2),
                height: max(300, contentHeight + DropShelfView.outerPadding * 2 + DropShelfView.headerHeight + 28)
            )
        }
    }

    private func preferredOrigin(for panel: NSPanel, size: CGSize) -> CGPoint {
        if panel.isVisible {
            return panel.frame.origin
        }

        if let lastKnownOrigin {
            return lastKnownOrigin
        }

        return CGPoint(
            x: NSEvent.mouseLocation.x - size.width / 2,
            y: NSEvent.mouseLocation.y - size.height / 2
        )
    }

    private func clampedOrigin(
        preferredOrigin: CGPoint,
        size: CGSize,
        visibleFrame: NSRect
    ) -> CGPoint {
        CGPoint(
            x: min(max(preferredOrigin.x, visibleFrame.minX + screenMargin), visibleFrame.maxX - size.width - screenMargin),
            y: min(max(preferredOrigin.y, visibleFrame.minY + screenMargin), visibleFrame.maxY - size.height - screenMargin)
        )
    }

    private func screenForMouseLocation() -> NSScreen {
        NSScreen.screens.first { screen in
            screen.frame.contains(NSEvent.mouseLocation)
        } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func screenForPanel(_ panel: NSPanel) -> NSScreen? {
        if panel.isVisible, let screen = panel.screen {
            return screen
        }

        if let lastKnownOrigin {
            return NSScreen.screens.first { screen in
                screen.frame.contains(lastKnownOrigin)
            }
        }

        return nil
    }
}

private final class DropShelfHostingView<Content: View>: NSHostingView<Content> {
    private weak var store: DropShelfViewModel?

    init(rootView: Content, store: DropShelfViewModel) {
        self.store = store
        super.init(rootView: rootView)
        registerForDraggedTypes(DropShelfPasteboardReader.supportedPasteboardTypes)
    }

    @available(*, unavailable)
    required init(rootView: Content) {
        fatalError("Use init(rootView:store:)")
    }

    @available(*, unavailable)
    @MainActor
    dynamic required init?(coder: NSCoder) {
        fatalError("Use init(rootView:store:)")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard store?.isInternalDragInProgress != true else {
            store?.setDropTargeted(false)
            return []
        }

        store?.setDropTargeted(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard store?.isInternalDragInProgress != true else {
            store?.setDropTargeted(false)
            return []
        }

        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        store?.setDropTargeted(false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        store?.setDropTargeted(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        store?.isInternalDragInProgress != true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard store?.isInternalDragInProgress != true else {
            store?.setDropTargeted(false)
            return false
        }

        return store?.addItems(from: sender.draggingPasteboard) ?? false
    }
}
