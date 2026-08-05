import AppKit
import SwiftUI

@MainActor
final class ToastPanelController {
    private var panel: NSPanel?
    private var hideWorkItem: DispatchWorkItem?

    func show(message: String, systemImage: String = "checkmark.circle.fill") {
        hideWorkItem?.cancel()

        let panel = panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(
            rootView: ToastView(message: message, systemImage: systemImage)
        )

        let size = ToastView.size
        let visibleFrame = screenForToast().visibleFrame
        let origin = CGPoint(
            x: visibleFrame.maxX - size.width - 18,
            y: visibleFrame.minY + 18
        )

        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()

        let workItem = DispatchWorkItem { [weak self] in
            self?.panel?.orderOut(nil)
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: workItem)
    }

    func hide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: ToastView.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isMovable = false
        panel.isOpaque = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating

        return panel
    }

    private func screenForToast() -> NSScreen {
        NSScreen.screens.first { screen in
            screen.frame.contains(NSEvent.mouseLocation)
        } ?? NSScreen.main ?? NSScreen.screens[0]
    }
}

private struct ToastView: View {
    static let size = CGSize(width: 236, height: 46)

    let message: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.green)

            Text(message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.22), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.24), radius: 12, y: 4)
    }
}
