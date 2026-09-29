import CoreGraphics
import Testing
@testable import screenshotapp

struct PinnedScreenshotLayoutTests {
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

    @Test func smallImageStartsAtActualSize() {
        #expect(PinnedScreenshotLayout.initialScale(imageSize: CGSize(width: 400, height: 300), visibleFrame: screen) == 1)
    }

    @Test func largeImageShrinksToFitScreen() {
        let scale = PinnedScreenshotLayout.initialScale(imageSize: CGSize(width: 2000, height: 800), visibleFrame: screen)
        #expect(scale == 0.4)
    }

    @Test func scaleIsClamped() {
        #expect(PinnedScreenshotLayout.clampedScale(0) == PinnedScreenshotLayout.minScale)
        #expect(PinnedScreenshotLayout.clampedScale(50) == PinnedScreenshotLayout.maxScale)
        #expect(PinnedScreenshotLayout.clampedScale(.nan) == 1)
        #expect(PinnedScreenshotLayout.scale(3.9, zoomedBy: 0.5) == PinnedScreenshotLayout.maxScale)
    }

    @Test func tinyContentKeepsMinimumSide() {
        let size = PinnedScreenshotLayout.contentSize(imageSize: CGSize(width: 100, height: 20), scale: 1)
        #expect(size == CGSize(width: 100, height: PinnedScreenshotLayout.minSide))
    }

    @Test func resizeKeepsCenter() {
        let frame = CGRect(x: 100, y: 100, width: 200, height: 100)
        let resized = PinnedScreenshotLayout.frame(resizing: frame, to: CGSize(width: 400, height: 200))
        #expect(resized == CGRect(x: 0, y: 50, width: 400, height: 200))
    }

    @Test func pinStartsCenteredOnScreen() {
        let frame = PinnedScreenshotLayout.centeredFrame(size: CGSize(width: 200, height: 100), in: screen)
        #expect(frame.midX == screen.midX && frame.midY == screen.midY)
    }
}
