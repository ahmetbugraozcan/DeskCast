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
        if settings.showPreviewsOnFocusedDisplay {
            return focusedApplicationScreen() ?? NSScreen.main ?? screenForMouseLocation()
        }

        return screenForMouseLocation()
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

    private func focusedApplicationScreen() -> NSScreen? {
        guard let frontmostApplication = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for window in windows {
            guard isCandidateFocusedWindow(window, processID: frontmostApplication.processIdentifier),
                  let bounds = windowBounds(from: window),
                  bounds.width > 40,
                  bounds.height > 40,
                  let screen = screen(containingWindowBounds: bounds) else {
                continue
            }

            return screen
        }

        return nil
    }

    private func isCandidateFocusedWindow(
        _ window: [String: Any],
        processID: pid_t
    ) -> Bool {
        let ownerPID = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
        let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue
        let isOnScreen = (window[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? true
        let alpha = (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1

        return ownerPID == processID
            && layer == 0
            && isOnScreen
            && alpha > 0
    }

    private func windowBounds(from window: [String: Any]) -> CGRect? {
        guard let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary else {
            return nil
        }

        return CGRect(dictionaryRepresentation: boundsDictionary)
    }

    private func screen(containingWindowBounds bounds: CGRect) -> NSScreen? {
        let candidateBounds = [
            bounds,
            flippedWindowBounds(bounds)
        ]

        return candidateBounds
            .flatMap { windowBounds in
                NSScreen.screens.compactMap { screen -> (screen: NSScreen, area: CGFloat)? in
                    let area = windowBounds.intersection(screen.frame).area
                    guard area > 0 else { return nil }

                    return (screen, area)
                }
            }
            .max { lhs, rhs in lhs.area < rhs.area }?
            .screen
    }

    private func flippedWindowBounds(_ bounds: CGRect) -> CGRect {
        let displayFrame = NSScreen.screens.reduce(CGRect.null) { result, screen in
            result.union(screen.frame)
        }

        guard !displayFrame.isNull else {
            return bounds
        }

        return CGRect(
            x: bounds.minX,
            y: displayFrame.maxY - bounds.maxY,
            width: bounds.width,
            height: bounds.height
        )
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else {
            return 0
        }

        return width * height
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
