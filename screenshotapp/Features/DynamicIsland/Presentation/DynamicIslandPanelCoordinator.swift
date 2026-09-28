import AppKit
import Combine
import SwiftUI

/// Owns the island's `NSPanel`: pins it to the top center of the notched (or
/// primary) display above the menu bar, and tracks the pointer so the panel only
/// takes mouse events while the pointer is over the island itself. Everywhere
/// else the transparent panel lets clicks through to the menu bar and windows.
@MainActor
final class DynamicIslandPanelCoordinator: DynamicIslandPresenting {
    private let store: DynamicIslandViewModel
    private var panel: DynamicIslandPanel?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var storeObserver: AnyCancellable?

    /// Extra slack around the collapsed island so it is easy to hit with the pointer.
    private static let collapsedHoverInset = CGSize(width: 10, height: 6)

    init(store: DynamicIslandViewModel) {
        self.store = store

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshIfVisible()
            }
        }

        // Re-evaluate the hover region whenever the island changes shape.
        storeObserver = store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateMouseInteraction()
                }
            }
    }

    var isVisible: Bool {
        panel?.isVisible == true
    }

    func refresh() {
        guard store.isEnabled, let screen = targetScreen() else {
            hide()
            return
        }

        let geometry = Self.geometry(for: screen)
        store.updateGeometry(geometry)

        let panel = panel ?? makePanel()
        self.panel = panel

        let size = DynamicIslandView.panelSize(for: geometry)
        let origin = CGPoint(
            x: (screen.frame.midX - size.width / 2).rounded(),
            y: screen.frame.maxY - size.height
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()

        installMouseMonitors()
        updateMouseInteraction()
    }

    func hide() {
        removeMouseMonitors()
        panel?.ignoresMouseEvents = true
        panel?.orderOut(nil)
    }

    private func refreshIfVisible() {
        guard isVisible else { return }
        refresh()
    }

    // MARK: - Panel

    private func makePanel() -> DynamicIslandPanel {
        let panel = DynamicIslandPanel(
            contentRect: NSRect(origin: .zero, size: DynamicIslandView.panelSize(for: store.geometry)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        let hostingView = DynamicIslandHostingView(rootView: DynamicIslandView(store: store))
        hostingView.sizingOptions = []
        panel.contentView = hostingView

        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isMovable = false
        panel.isOpaque = false
        panel.isReleasedWhenClosed = false
        // Above the menu bar so the island can sit over (and grow out of) the notch.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        // Keep the island out of DeskCast's own screenshots and other captures.
        panel.sharingType = .none

        return panel
    }

    private func targetScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.screens.first
    }

    private static func geometry(for screen: NSScreen) -> DynamicIslandGeometry {
        if screen.safeAreaInsets.top > 0,
           let leftArea = screen.auxiliaryTopLeftArea,
           let rightArea = screen.auxiliaryTopRightArea {
            let notchWidth = screen.frame.width - leftArea.width - rightArea.width

            return DynamicIslandGeometry(
                notchSize: CGSize(width: max(notchWidth, 120), height: screen.safeAreaInsets.top),
                hasNotch: true
            )
        }

        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        let height = menuBarHeight > 0 ? menuBarHeight : NSStatusBar.system.thickness

        return DynamicIslandGeometry(
            notchSize: CGSize(width: DynamicIslandGeometry.fallback.notchSize.width, height: max(height, 24)),
            hasNotch: false
        )
    }

    // MARK: - Pointer tracking

    private func installMouseMonitors() {
        guard globalMouseMonitor == nil, localMouseMonitor == nil else { return }

        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]

        // Mouse-move monitoring does not need Accessibility permission.
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateMouseInteraction()
            }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            MainActor.assumeIsolated {
                self?.updateMouseInteraction()
            }
            return event
        }
    }

    private func removeMouseMonitors() {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
        }

        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
        }

        globalMouseMonitor = nil
        localMouseMonitor = nil
    }

    private func updateMouseInteraction() {
        guard let panel, panel.isVisible else { return }

        let isInside = hoverRect(in: panel.frame).contains(NSEvent.mouseLocation)
        panel.ignoresMouseEvents = !isInside
        store.setHovering(isInside)
    }

    /// The island's current on-screen rect (top-center of the panel), padded
    /// while collapsed so the small shape is forgiving to hit.
    private func hoverRect(in panelFrame: NSRect) -> NSRect {
        let mode = store.mode
        let size = DynamicIslandView.islandSize(
            for: mode,
            geometry: store.geometry,
            hasMedia: store.hasMedia
        )
        let rect = NSRect(
            x: panelFrame.midX - size.width / 2,
            y: panelFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )

        guard mode != .expanded else { return rect }

        let inset = Self.collapsedHoverInset
        return NSRect(
            x: rect.minX - inset.width,
            y: rect.minY - inset.height,
            width: rect.width + inset.width * 2,
            height: rect.height + inset.height
        )
    }
}

private final class DynamicIslandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class DynamicIslandHostingView<Content: View>: NSHostingView<Content> {
    // The panel never becomes key, so the first click must reach the controls.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
