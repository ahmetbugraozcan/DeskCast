import AppKit

extension ScreenshotShelfViewModel {
    /// Removes the item from the shelf and moves its file to the Trash, so it's
    /// deleted from disk but still recoverable from the Trash.
    func moveToTrash(_ item: ScreenshotItem) {
        if let fileURL = item.fileURL, FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                try FileManager.default.trashItem(at: fileURL, resultingItemURL: nil)
            } catch {
                NSSound.beep()
                showToast(
                    AppLocalization.string("Could not move to Trash"),
                    systemImage: "exclamationmark.triangle.fill"
                )
                return
            }
        }

        removeScreenshot(withID: item.id)
        showToast(AppLocalization.string("Moved to Trash"), systemImage: "trash")
    }
}
