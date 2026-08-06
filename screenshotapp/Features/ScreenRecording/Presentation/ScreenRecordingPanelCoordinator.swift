import AppKit
import SwiftUI

private final class ScreenRecordingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
protocol ScreenRecordingPresenting: AnyObject {
    func showControlPanel()
    func refreshControlPanel()
    func hideControlPanel()
    func showSelectionOverlay(
        on display: ScreenRecordingDisplay,
        initialRect: CGRect?,
        completion: @escaping (CGRect?) -> Void
    )
    func showRecordingIndicator(on display: ScreenRecordingDisplay, rect: CGRect)
    func hideRecordingIndicator()
    func showCountdown(_ value: Int)
    func hideCountdown()
}

@MainActor
final class ScreenRecordingPanelCoordinator: ScreenRecordingPresenting {
    private let store: ScreenRecordingViewModel
    private var controlPanel: NSPanel?
    private var selectionPanel: NSPanel?
    private var recordingIndicatorPanel: NSPanel?
    private var countdownPanel: NSPanel?
    private let countdownModel = CountdownOverlayModel()

    init(store: ScreenRecordingViewModel) {
        self.store = store
    }

    func showControlPanel() {
        let panel = controlPanel ?? makeControlPanel()
        controlPanel = panel
        positionControlPanel(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func refreshControlPanel() {
        guard let controlPanel else { return }
        positionControlPanel(controlPanel)
        controlPanel.orderFrontRegardless()
    }

    func hideControlPanel() {
        controlPanel?.orderOut(nil)
    }

    func showSelectionOverlay(
        on display: ScreenRecordingDisplay,
        initialRect: CGRect?,
        completion: @escaping (CGRect?) -> Void
    ) {
        selectionPanel?.orderOut(nil)

        let panel = ScreenRecordingPanel(
            contentRect: display.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hasShadow = false
        panel.isMovable = false
        panel.isOpaque = false
        panel.level = .screenSaver
        panel.contentView = NSHostingView(
            rootView: ScreenAreaSelectionView(
                initialRect: initialRect,
                onComplete: { [weak self] rect in
                    self?.selectionPanel?.orderOut(nil)
                    self?.selectionPanel = nil
                    self?.showControlPanel()
                    completion(rect)
                }
            )
        )
        selectionPanel = panel
        controlPanel?.orderOut(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func showRecordingIndicator(on display: ScreenRecordingDisplay, rect: CGRect) {
        recordingIndicatorPanel?.orderOut(nil)

        // `rect` is display-local with a top-left origin (points). Convert it to a
        // global, bottom-left Cocoa frame so the borderless overlay hugs the region.
        let globalFrame = NSRect(
            x: display.frame.minX + rect.minX,
            y: display.frame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )

        let panel = ScreenRecordingPanel(
            contentRect: globalFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hasShadow = false
        panel.isMovable = false
        panel.isOpaque = false
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.contentView = NSHostingView(rootView: ScreenRecordingAreaIndicatorView())
        recordingIndicatorPanel = panel
        panel.orderFrontRegardless()
    }

    func hideRecordingIndicator() {
        recordingIndicatorPanel?.orderOut(nil)
        recordingIndicatorPanel = nil
    }

    func showCountdown(_ value: Int) {
        countdownModel.value = value

        if countdownPanel == nil {
            let screen = activeScreen()
            let panel = ScreenRecordingPanel(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            panel.backgroundColor = .clear
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.hasShadow = false
            panel.isMovable = false
            panel.isOpaque = false
            panel.ignoresMouseEvents = true
            panel.level = .screenSaver
            panel.contentView = NSHostingView(
                rootView: ScreenRecordingCountdownView(model: countdownModel)
            )
            countdownPanel = panel
        }

        countdownPanel?.orderFrontRegardless()
    }

    func hideCountdown() {
        countdownPanel?.orderOut(nil)
        countdownPanel = nil
    }

    private func activeScreen() -> NSScreen {
        NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func makeControlPanel() -> NSPanel {
        let size = ScreenRecordingControlView.panelSize
        let panel = ScreenRecordingPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // The control view draws its own rounded shadow; a window shadow would be
        // rectangular and leak a dark frame past the rounded corners.
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.contentView = NSHostingView(rootView: ScreenRecordingControlView(store: store))
        return panel
    }

    private func positionControlPanel(_ panel: NSPanel) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? panel.screen
            ?? NSScreen.main
            ?? NSScreen.screens[0]
        let visibleFrame = screen.visibleFrame
        let size = ScreenRecordingControlView.panelSize
        panel.setFrame(
            NSRect(
                x: visibleFrame.midX - size.width / 2,
                y: visibleFrame.minY + 34,
                width: size.width,
                height: size.height
            ),
            display: true,
            animate: panel.isVisible
        )
    }
}
