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
    private let panels: IslandPanelModels
    private var panel: DynamicIslandPanel?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalClickMonitor: Any?
    private var localKeyMonitor: Any?
    private var localScrollMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var storeObserver: AnyCancellable?
    private var fullScreenCheckTask: Task<Void, Never>?
    /// A full-screen app covers the island's screen ("Hide in full screen").
    private var isCoveredByFullScreenApp = false
    private var scrollTravel = CGSize.zero
    private var scrollGestureHandled = false
    private var lastWheelSwipe = Date.distantPast

    /// Extra slack around the collapsed island so it is easy to hit with the pointer.
    private static let collapsedHoverInset = CGSize(width: 10, height: 6)

    init(store: DynamicIslandViewModel, panels: IslandPanelModels) {
        self.store = store
        self.panels = panels

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshIfVisible()
            }
        }

        // Full-screen apps live in their own Space and activate on entry.
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didActivateApplicationNotification
        ].map { name in
            workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.scheduleFullScreenCheck()
                }
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

        isCoveredByFullScreenApp = store.preferences.hidesInFullScreen && Self.isFullScreenAppActive(on: screen)

        guard !isCoveredByFullScreenApp else {
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
        panel.sharingType = sharingType
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

    /// Entering or leaving full screen animates for a moment before the
    /// window reaches its final frame, so check again once it settles.
    private func scheduleFullScreenCheck() {
        fullScreenCheckTask?.cancel()

        guard store.isEnabled, store.preferences.hidesInFullScreen || isCoveredByFullScreenApp else { return }

        fullScreenCheckTask = Task { [weak self] in
            for delay in [0.1, 0.8] {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self, let screen = self.targetScreen() else { return }

                let isCovered = self.store.preferences.hidesInFullScreen && Self.isFullScreenAppActive(on: screen)

                if isCovered != self.isCoveredByFullScreenApp {
                    self.refresh()
                }
            }
        }
    }

    /// The frontmost app has a window covering the whole screen (including
    /// the menu bar area), which only full-screen windows do. Window bounds
    /// are readable without Screen Recording permission.
    private static func isFullScreenAppActive(on screen: NSScreen) -> Bool {
        guard
            let frontmost = NSWorkspace.shared.frontmostApplication,
            frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier,
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else {
            return false
        }

        // Window bounds are top-left based, relative to the primary screen.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let screenBounds = CGRect(
            x: screen.frame.minX,
            y: primaryHeight - screen.frame.maxY,
            width: screen.frame.width,
            height: screen.frame.height
        )

        return windows.contains { info in
            guard
                (info[kCGWindowOwnerPID as String] as? pid_t) == frontmost.processIdentifier,
                (info[kCGWindowLayer as String] as? Int) == 0,
                let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsInfo)
            else {
                return false
            }

            return bounds == screenBounds
        }
    }

    private var sharingType: NSWindow.SharingType {
        #if DEBUG
        // CI screenshots (`-DeskCastAllowsIslandCapture YES`) need the island visible.
        if UserDefaults.standard.bool(forKey: "DeskCastAllowsIslandCapture") {
            return .readOnly
        }
        #endif

        return store.preferences.showsInCaptures ? .readOnly : .none
    }

    // MARK: - Panel

    private func makePanel() -> DynamicIslandPanel {
        let panel = DynamicIslandPanel(
            contentRect: NSRect(origin: .zero, size: DynamicIslandView.panelSize(for: store.geometry)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        let hostingView = DynamicIslandHostingView(rootView: DynamicIslandView(store: store, panels: panels))
        hostingView.sizingOptions = []
        hostingView.registerForDraggedTypes(DropShelfPasteboardReader.supportedPasteboardTypes)
        hostingView.onDragEntered = { [weak self] in
            guard let self, self.store.preferences.visiblePanels.contains(.files) else { return false }
            self.store.beginFileDrag()
            return true
        }
        hostingView.onDrop = { [weak self] pasteboard in
            self?.panels.dropShelf.addItems(from: pasteboard, revealsShelf: false) ?? false
        }
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
        // Unless "Show in screenshots and recordings" is on, keep the island
        // out of DeskCast's own screenshots and other captures.
        panel.sharingType = sharingType

        return panel
    }

    private func targetScreen() -> NSScreen? {
        let screens = NSScreen.screens
        // The first screen is the one with the menu bar.
        let mainScreen = screens.first

        switch store.preferences.displayTarget {
        case .automatic:
            return screens.first { $0.safeAreaInsets.top > 0 } ?? mainScreen
        case .builtIn:
            return screens.first(where: Self.isBuiltIn) ?? mainScreen
        case .main:
            return mainScreen
        }
    }

    private static func isBuiltIn(_ screen: NSScreen) -> Bool {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return false
        }

        return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0
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

        // Global click events only arrive for clicks outside DeskCast's windows,
        // i.e. outside the island, which closes a click/shortcut-opened island.
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.store.handleOutsideClick()
            }
        }

        // The panel takes mouse events only while the pointer is on the island,
        // so its scroll events are the swipes made over the island.
        localScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let handled = MainActor.assumeIsolated {
                self?.handleScroll(event) ?? false
            }
            return handled ? nil : event
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Escape closes the island (reachable while the scratchpad has focus).
            let isEscape = event.keyCode == 53
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard isEscape, let self, self.panel?.isKeyWindow == true else { return false }
                self.store.collapse()
                self.panel?.resignKey()
                return true
            }
            return handled ? nil : event
        }
    }

    private func removeMouseMonitors() {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
        }

        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
        }

        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
        }

        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }

        if let localScrollMonitor {
            NSEvent.removeMonitor(localScrollMonitor)
        }

        globalMouseMonitor = nil
        localMouseMonitor = nil
        globalClickMonitor = nil
        localKeyMonitor = nil
        localScrollMonitor = nil
    }

    // MARK: - Gestures

    /// Swipe distance (points) before a trackpad gesture counts.
    private static let swipeThreshold: CGFloat = 24
    /// Minimum gap between mouse-wheel swipes, which arrive as separate clicks.
    private static let wheelSwipeInterval: TimeInterval = 0.35
    /// Height of the island's top row, where swiping up closes it.
    private static let topRowExtraHeight: CGFloat = 36

    /// Turns scrolls over the island into swipes: down opens, up (in the top
    /// row) closes, sideways over music changes the track. Returns whether
    /// the event was used, so it doesn't also scroll the panel's lists.
    private func handleScroll(_ event: NSEvent) -> Bool {
        guard let panel, event.window === panel, store.preferences.gesturesEnabled else { return false }

        // Momentum after a swipe belongs to the swipe that already fired.
        guard event.momentumPhase.isEmpty else { return scrollGestureHandled }

        let topOffset = panel.frame.height - event.locationInWindow.y
        let inTopRow = topOffset <= store.geometry.notchSize.height + Self.topRowExtraHeight

        // Finger movement: with natural scrolling the deltas already follow the fingers.
        let sign: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
        let delta = CGSize(width: event.scrollingDeltaX * sign, height: event.scrollingDeltaY * sign)

        guard event.hasPreciseScrollingDeltas else {
            // Mouse wheel: one notch is one swipe, rate-limited.
            guard Date().timeIntervalSince(lastWheelSwipe) > Self.wheelSwipeInterval,
                  let direction = Self.direction(of: delta, threshold: 0.5)
            else {
                return false
            }

            let handled = performSwipe(direction, inTopRow: inTopRow)
            if handled { lastWheelSwipe = Date() }
            return handled
        }

        if event.phase.contains(.began) {
            scrollTravel = .zero
            scrollGestureHandled = false
        }

        guard !scrollGestureHandled else { return true }

        scrollTravel.width += delta.width
        scrollTravel.height += delta.height

        guard let direction = Self.direction(of: scrollTravel, threshold: Self.swipeThreshold) else { return false }

        scrollGestureHandled = performSwipe(direction, inTopRow: inTopRow)

        // Keep a vertical scroll that didn't trigger a swipe scrolling the list.
        if !scrollGestureHandled {
            scrollTravel = .zero
        }

        return scrollGestureHandled
    }

    private func performSwipe(_ direction: IslandSwipeDirection, inTopRow: Bool) -> Bool {
        guard store.handleSwipe(direction, inTopRow: inTopRow) else { return false }

        if store.preferences.hapticsEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }

        return true
    }

    private static func direction(of travel: CGSize, threshold: CGFloat) -> IslandSwipeDirection? {
        if abs(travel.height) >= abs(travel.width) {
            guard abs(travel.height) >= threshold else { return nil }
            return travel.height > 0 ? .down : .up
        }

        guard abs(travel.width) >= threshold else { return nil }
        return travel.width > 0 ? .right : .left
    }

    private func updateMouseInteraction() {
        guard let panel, panel.isVisible else { return }

        let wantsKeyboard = store.mode == .expanded && store.expandedContent == .panel(.scratchpad)
        panel.allowsKey = wantsKeyboard

        if !wantsKeyboard, panel.isKeyWindow {
            panel.resignKey()
        }

        let location = NSEvent.mouseLocation
        // While the scratchpad has keyboard focus, keep the island open even if
        // the pointer wanders off; clicking elsewhere resigns key and closes it.
        let isInside = hoverRects(in: panel.frame).contains { $0.contains(location) }
            || (wantsKeyboard && panel.isKeyWindow)

        panel.ignoresMouseEvents = !isInside
        store.setHovering(isInside)
    }

    /// The island and its side buttons in screen coordinates, padded while
    /// collapsed so the small shape is forgiving to hit.
    private func hoverRects(in panelFrame: NSRect) -> [NSRect] {
        let layout = DynamicIslandView.layout(for: store)
        let isExpanded = store.mode == .expanded

        return layout.interactiveFrames.map { frame in
            // SwiftUI frames are top-left based; screen space is bottom-left.
            // With the pointer pushed against the top of the screen its y is the
            // screen's maxY, which `contains` excludes; reach 1 pt past the top.
            let touchesTop = frame.minY <= 0
            let rect = NSRect(
                x: panelFrame.minX + frame.minX,
                y: panelFrame.maxY - frame.maxY,
                width: frame.width,
                height: frame.height + (touchesTop ? 1 : 0)
            )

            guard !isExpanded else { return rect }

            let inset = Self.collapsedHoverInset
            return NSRect(
                x: rect.minX - inset.width,
                y: rect.minY - inset.height,
                width: rect.width + inset.width * 2,
                height: rect.height + inset.height
            )
        }
    }
}

private final class DynamicIslandPanel: NSPanel {
    /// Only the scratchpad needs typing; otherwise the panel never steals focus.
    var allowsKey = false

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
}

private final class DynamicIslandHostingView<Content: View>: NSHostingView<Content> {
    /// Returns whether the island takes the drag (it then opens the Files panel).
    var onDragEntered: (() -> Bool)?
    var onDrop: ((NSPasteboard) -> Bool)?

    // The panel never becomes key, so the first click must reach the controls.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDragEntered?() == true ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDrop == nil ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onDrop?(sender.draggingPasteboard) ?? false
    }
}
