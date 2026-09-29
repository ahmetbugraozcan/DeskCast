import CoreGraphics

/// Size math for a screenshot pinned on screen: the window shows the image at
/// `scale` of its point size, starts fitted inside the screen, and resizes
/// around its center.
nonisolated enum PinnedScreenshotLayout {
    static let minScale: CGFloat = 0.1
    static let maxScale: CGFloat = 4
    static let minSide: CGFloat = 48
    /// Largest share of the visible screen a newly pinned image may cover.
    static let initialScreenFraction: CGFloat = 0.8
    static let opacityOptions: [Double] = [1, 0.75, 0.5, 0.25]
    static let scaleOptions: [CGFloat] = [0.5, 1, 1.5, 2]

    static func clampedScale(_ scale: CGFloat) -> CGFloat {
        guard scale.isFinite else { return 1 }
        return min(max(scale, minScale), maxScale)
    }

    /// Starts at 100 % unless the image doesn't fit, then shrinks to fit.
    static func initialScale(imageSize: CGSize, visibleFrame: CGRect) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
        let fit = min(
            visibleFrame.width * initialScreenFraction / imageSize.width,
            visibleFrame.height * initialScreenFraction / imageSize.height
        )
        return clampedScale(min(1, fit))
    }

    static func contentSize(imageSize: CGSize, scale: CGFloat) -> CGSize {
        let scale = clampedScale(scale)
        return CGSize(
            width: max((imageSize.width * scale).rounded(), minSide),
            height: max((imageSize.height * scale).rounded(), minSide)
        )
    }

    /// Keeps the window's center fixed while it grows or shrinks.
    static func frame(resizing frame: CGRect, to size: CGSize) -> CGRect {
        CGRect(
            x: (frame.midX - size.width / 2).rounded(),
            y: (frame.midY - size.height / 2).rounded(),
            width: size.width,
            height: size.height
        )
    }

    static func centeredFrame(size: CGSize, in visibleFrame: CGRect) -> CGRect {
        frame(resizing: CGRect(x: visibleFrame.midX, y: visibleFrame.midY, width: 0, height: 0), to: size)
    }

    /// Scroll-wheel/pinch step: proportional, so zooming feels the same at any size.
    static func scale(_ scale: CGFloat, zoomedBy delta: CGFloat) -> CGFloat {
        clampedScale(scale * (1 + delta))
    }
}
