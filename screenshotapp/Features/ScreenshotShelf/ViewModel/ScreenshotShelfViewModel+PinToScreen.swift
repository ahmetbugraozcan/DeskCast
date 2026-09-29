import AppKit

extension ScreenshotShelfViewModel {
    /// Floats the capture above other windows in its own panel; the shelf item
    /// stays, and the pinned copy lives until the user closes it.
    func pinToScreen(_ item: ScreenshotItem) {
        guard !item.isVideo else { return }
        presenter?.pinToScreen(item)
    }

    /// ⌘C / Copy from a pinned screenshot, which may outlive its shelf item.
    func copyPinnedScreenshot(_ item: ScreenshotItem) {
        copy(item)
        showToast(AppLocalization.string("Copied to clipboard"), systemImage: "doc.on.doc")
    }
}

#if DEBUG
extension ScreenshotShelfViewModel {
    /// Debug builds only: `-DeskCastDemoPin YES` pins a sample image for UI checks.
    func pinDemoScreenshotIfRequested() {
        guard UserDefaults.standard.bool(forKey: "DeskCastDemoPin") else { return }
        pinToScreen(ScreenshotItem(image: Self.demoImage, isPinned: false))
    }

    /// Debug builds only: `-DeskCastDemoAnnotate YES` opens the annotation editor on a sample image.
    func annotateDemoScreenshotIfRequested() {
        guard UserDefaults.standard.bool(forKey: "DeskCastDemoAnnotate") else { return }
        annotate(ScreenshotItem(image: Self.demoImage, isPinned: false))
    }

    private static var demoImage: NSImage {
        NSImage(size: CGSize(width: 520, height: 320), flipped: false) { rect in
            NSGradient(starting: .systemIndigo, ending: .systemTeal)?.draw(in: rect, angle: 35)
            let text = NSAttributedString(
                string: "DeskCast",
                attributes: [.font: NSFont.systemFont(ofSize: 56, weight: .bold), .foregroundColor: NSColor.white]
            )
            text.draw(at: CGPoint(x: rect.midX - text.size().width / 2, y: rect.midY - text.size().height / 2))
            return true
        }
    }
}
#endif
