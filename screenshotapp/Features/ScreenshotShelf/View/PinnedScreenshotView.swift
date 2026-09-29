import AppKit
import SwiftUI

/// Content of a screenshot pinned on screen: the image fills the window, hover
/// shows close/copy/zoom/opacity controls, and the image itself moves the
/// window (drag) or resizes it (scroll or pinch).
struct PinnedScreenshotView: View {
    let image: NSImage
    @ObservedObject var state: PinnedScreenshotState
    let closeAction: () -> Void
    let copyAction: () -> Void

    @State private var isHovering = false

    private static let cornerRadius: CGFloat = 6

    var body: some View {
        ZStack(alignment: .top) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)

            PinnedScreenshotInteractionView { delta in
                state.scale = PinnedScreenshotLayout.scale(state.scale, zoomedBy: delta)
            }
            .help(Text(AppLocalization.string("pin.hint")))

            toolbar
                .padding(6)
                .opacity(isHovering ? 1 : 0)
                .allowsHitTesting(isHovering)
                .animation(.easeInOut(duration: 0.15), value: isHovering)
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(isHovering ? Color.accentColor.opacity(0.8) : Color.black.opacity(0.18), lineWidth: 1)
        )
        .onHover { isHovering = $0 }
        .contextMenu { menuItems }
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            PinnedToolbarButton(systemName: "xmark", help: AppLocalization.string("Close"), action: closeAction)
            Spacer(minLength: 0)
            Text(verbatim: "\(Int((state.scale * 100).rounded())) %")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 6)
                .frame(height: 22)
                .background(.regularMaterial, in: Capsule())
            Menu {
                menuItems
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 22, height: 22)
                    .background(.regularMaterial, in: Circle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            PinnedToolbarButton(systemName: "doc.on.doc", help: AppLocalization.string("Copy"), action: copyAction)
        }
    }

    @ViewBuilder
    private var menuItems: some View {
        Button {
            copyAction()
        } label: {
            Label(AppLocalization.string("Copy Image"), systemImage: "doc.on.doc")
        }

        Menu {
            ForEach(PinnedScreenshotLayout.scaleOptions, id: \.self) { scale in
                Toggle(isOn: Binding(get: { state.scale == scale }, set: { _ in state.scale = scale })) {
                    Text(verbatim: "\(Int(scale * 100)) %")
                }
            }
        } label: {
            Label(AppLocalization.string("Size"), systemImage: "arrow.up.left.and.arrow.down.right")
        }

        Menu {
            ForEach(PinnedScreenshotLayout.opacityOptions, id: \.self) { opacity in
                Toggle(isOn: Binding(get: { state.opacity == opacity }, set: { _ in state.opacity = opacity })) {
                    Text(verbatim: "\(Int(opacity * 100)) %")
                }
            }
        } label: {
            Label(AppLocalization.string("pin.opacity"), systemImage: "circle.lefthalf.filled")
        }

        Divider()

        Button(role: .destructive) {
            closeAction()
        } label: {
            Label(AppLocalization.string("Close"), systemImage: "xmark")
        }
    }
}

private struct PinnedToolbarButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 22, height: 22)
                .background(.regularMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Moves the window when the image is dragged and reports zoom steps from the
/// scroll wheel and trackpad pinch.
private struct PinnedScreenshotInteractionView: NSViewRepresentable {
    let zoom: (CGFloat) -> Void

    func makeNSView(context: Context) -> PinnedScreenshotInteractionNSView {
        let view = PinnedScreenshotInteractionNSView()
        view.zoom = zoom
        return view
    }

    func updateNSView(_ nsView: PinnedScreenshotInteractionNSView, context: Context) {
        nsView.zoom = zoom
    }
}

private final class PinnedScreenshotInteractionNSView: NSView {
    var zoom: (CGFloat) -> Void = { _ in }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.performDrag(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        // Trackpads report pixel deltas, mouse wheels report lines.
        let step: CGFloat = event.hasPreciseScrollingDeltas ? 0.004 : 0.08
        let delta = event.scrollingDeltaY * step
        guard delta != 0 else { return }
        zoom(max(min(delta, 0.5), -0.5))
    }

    override func magnify(with event: NSEvent) {
        zoom(event.magnification)
    }
}
