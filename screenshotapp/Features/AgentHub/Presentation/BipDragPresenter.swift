import AppKit
import SwiftUI

/// The AppKit side of dragging Bip out of the island onto a window: a Bip
/// that follows the pointer, and a glowing halo around the window it was
/// dropped on while that window is the conversation's context.
@MainActor
protocol BipDragPresenting: AnyObject {
    func showGhost(at point: CGPoint)
    func moveGhost(to point: CGPoint)
    func hideGhost()
    func showHalo(around frame: CGRect)
    func hideHalo()
}

final class BipDragPresenter: BipDragPresenting {
    private var ghost: NSPanel?
    private var halo: NSPanel?

    private static let ghostSize: CGFloat = 64
    private static let haloInset: CGFloat = 6

    func showGhost(at point: CGPoint) {
        let panel = ghost ?? Self.makePanel(
            size: CGSize(width: Self.ghostSize, height: Self.ghostSize),
            content: BipMascotView(mood: .happy, size: Self.ghostSize, isInteractive: false)
        )
        ghost = panel
        moveGhost(to: point)
        panel.orderFrontRegardless()
    }

    func moveGhost(to point: CGPoint) {
        ghost?.setFrameOrigin(CGPoint(x: point.x - Self.ghostSize / 2, y: point.y - Self.ghostSize / 2))
    }

    func hideGhost() {
        ghost?.orderOut(nil)
        ghost = nil
    }

    func showHalo(around frame: CGRect) {
        hideHalo()
        let rect = frame.insetBy(dx: -Self.haloInset, dy: -Self.haloInset)
        let panel = Self.makePanel(size: rect.size, content: WindowHaloView())
        panel.setFrame(rect, display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.6
            panel.animator().alphaValue = 1
        }
        halo = panel
    }

    func hideHalo() {
        guard let halo else { return }
        self.halo = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            halo.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated { halo.orderOut(nil) }
        }
    }

    private static func makePanel<Content: View>(size: CGSize, content: Content) -> NSPanel {
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        panel.sharingType = .none
        let host = NSHostingView(rootView: content)
        host.frame = CGRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        return panel
    }
}

/// A rainbow border that slowly turns, over a soft colored veil.
private struct WindowHaloView: View {
    private static let colors: [Color] = [
        Color(red: 1, green: 0.42, blue: 0.36), Color(red: 0.97, green: 0.7, blue: 0.17),
        Color(red: 0.18, green: 0.83, blue: 0.65), Color(red: 0.22, green: 0.74, blue: 0.97),
        Color(red: 0.65, green: 0.55, blue: 0.98), Color(red: 0.96, green: 0.45, blue: 0.71),
        Color(red: 1, green: 0.42, blue: 0.36)
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let angle = Angle.degrees(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3) / 3 * 360)
            let breath = 0.06 + 0.04 * sin(context.date.timeIntervalSinceReferenceDate * 2)
            let gradient = AngularGradient(colors: Self.colors, center: .center, angle: angle)

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(gradient)
                    .opacity(breath)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(gradient, lineWidth: 3)
                    .shadow(color: .white.opacity(0.25), radius: 6)
            }
        }
    }
}
