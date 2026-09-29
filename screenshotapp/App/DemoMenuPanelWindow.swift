#if DEBUG
import AppKit
import SwiftUI

/// Debug builds only: `-DeskCastDemoMenuPanel YES` shows the menu bar panel in
/// a plain window, since CI can't click the status item to open the real one.
@MainActor
enum DemoMenuPanelWindow {
    private static var window: NSPanel?

    static func showIfRequested(environment: AppEnvironment) {
        guard UserDefaults.standard.bool(forKey: "DeskCastDemoMenuPanel"), let screen = NSScreen.main else { return }

        let defaults = UserDefaults.standard
        func isVisible(_ tool: ToolboxToolID) -> Bool {
            defaults.bool(forKey: tool.enabledKey) && defaults.bool(forKey: tool.showInMenuKey)
        }

        let view = MenuBarPanelView(
            screenshots: environment.screenshotShelf,
            recorder: environment.screenRecorder,
            dropShelf: environment.dropShelf,
            island: environment.dynamicIsland,
            colorPicker: environment.colorPicker,
            visibility: MenuBarPanelVisibility(
                captureSelectedArea: isVisible(.captureSelectedArea),
                captureVideo: isVisible(.captureVideo),
                captureOCR: isVisible(.captureOCR),
                pickColor: isVisible(.pickColor),
                imageSearch: isVisible(.imageSearch),
                copyFinderPath: isVisible(.copyFinderPath),
                dropShelf: isVisible(.dropShelf),
                dynamicIsland: isVisible(.dynamicIsland)
            ),
            actions: MenuBarPanelActions(openImageSearch: {}, openSettings: {}, quit: {})
        )
        .background(.regularMaterial)

        let hostingView = NSHostingView(rootView: view)
        let size = hostingView.fittingSize
        let panel = NSPanel(
            contentRect: NSRect(
                x: screen.visibleFrame.maxX - size.width - 80,
                y: screen.visibleFrame.maxY - size.height - 8,
                width: size.width,
                height: size.height
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.level = .statusBar
        panel.orderFrontRegardless()
        window = panel
    }
}
#endif
