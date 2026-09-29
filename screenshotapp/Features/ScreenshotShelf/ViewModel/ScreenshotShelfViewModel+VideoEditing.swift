import AppKit

extension ScreenshotShelfViewModel {
    /// Opens the Trim / GIF window for a recorded video.
    func editVideo(_ item: ScreenshotItem) {
        guard item.isVideo, let fileURL = item.fileURL else { return }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            videoEditFailed(AppLocalization.string("videoEdit.missing"))
            return
        }
        presenter?.showVideoEditor(for: item)
    }

    /// The trimmed copy joins the shelf next to the original, which is kept.
    func trimmedVideoSaved(at url: URL) {
        addVideo(at: url)
        showToast(AppLocalization.formatted("Saved %@", url.lastPathComponent), systemImage: "scissors")
    }

    /// A GIF can't live on the shelf as a still image without losing its
    /// animation, so its file is copied instead, ready to paste into a chat.
    func gifExported(at url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
        showToast(AppLocalization.formatted("videoEdit.gif.saved", url.lastPathComponent), systemImage: "photo.stack")
    }

    func videoEditFailed(_ message: String) {
        NSSound.beep()
        showToast(message, systemImage: "exclamationmark.triangle.fill")
    }
}

#if DEBUG
extension ScreenshotShelfViewModel {
    /// Debug builds only: `-DeskCastDemoVideo <path>` opens the Trim / GIF window on that video.
    func editDemoVideoIfRequested() {
        guard let path = UserDefaults.standard.string(forKey: "DeskCastDemoVideo") else { return }
        let url = URL(fileURLWithPath: path)
        editVideo(ScreenshotItem(videoThumbnail: NSImage(), durationSeconds: nil, fileURL: url, isPinned: false))
    }
}
#endif
