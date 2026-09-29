import AppKit

extension ScreenshotShelfViewModel {
    func openInPreview(_ item: ScreenshotItem) {
        if item.isVideo, let fileURL = item.fileURL {
            NSWorkspace.shared.open(fileURL)
            return
        }

        do {
            let url = try TemporaryPNGWriter.write(item.image)
            let configuration = NSWorkspace.OpenConfiguration()
            let previewURL = URL(fileURLWithPath: "/System/Applications/Preview.app")

            NSWorkspace.shared.open(
                [url],
                withApplicationAt: previewURL,
                configuration: configuration
            )
        } catch {
            NSSound.beep()
        }
    }

    /// Opens the annotation editor for an image capture.
    func annotate(_ item: ScreenshotItem) {
        guard !item.isVideo else { return }
        presenter?.showAnnotationEditor(for: item)
    }

    /// Replaces the capture with its annotated version and, when it was
    /// already saved as a PNG, rewrites that file too.
    func applyAnnotatedImage(_ image: NSImage, toItemWithID id: UUID) {
        guard let item = replaceImage(image, forID: id) else {
            // The capture left the shelf while it was being edited; keep the work.
            copyAnnotatedImage(image)
            return
        }

        guard let fileURL = item.fileURL,
              fileURL.pathExtension.lowercased() == "png",
              FileManager.default.fileExists(atPath: fileURL.path) else {
            showToast(AppLocalization.string("annotate.applied"), systemImage: "pencil.tip.crop.circle")
            return
        }

        do {
            guard let data = image.tinyShotShelfPNGData else { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: fileURL, options: .atomic)
            showToast(AppLocalization.formatted("Saved %@", fileURL.lastPathComponent), systemImage: "pencil.tip.crop.circle")
        } catch {
            NSSound.beep()
            showToast(AppLocalization.string("Could not save image"), systemImage: "exclamationmark.triangle.fill")
        }
    }

    func copyAnnotatedImage(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        showToast(AppLocalization.string("Copied to clipboard"), systemImage: "doc.on.doc")
    }
}
