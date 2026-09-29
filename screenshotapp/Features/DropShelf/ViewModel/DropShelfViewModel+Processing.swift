import AppKit
import UniformTypeIdentifiers

/// Convert, resize and zip actions. The work runs off the main thread; the
/// results join the shelf next to their source, so they can be dragged out.
extension DropShelfViewModel {
    /// Image items (dropped image files or raw images) can be converted.
    func canProcessImage(_ item: DropShelfItem) -> Bool {
        if item.image != nil {
            return true
        }

        guard let fileURL = item.fileURL, !fileURL.hasDirectoryPath else { return false }
        return UTType(filenameExtension: fileURL.pathExtension)?.conforms(to: .image) == true
    }

    func convertImage(_ item: DropShelfItem, to format: ShelfImageFormat, resize: ShelfImageResize? = nil) {
        guard canProcessImage(item), let sourceURL = try? exporter.previewURL(for: item) else {
            NSSound.beep()
            return
        }

        let processor = processor
        runProcessing(after: item) {
            try [processor.convertImage(at: sourceURL, to: format, resize: resize)]
        } message: { _ in
            resize == nil
                ? AppLocalization.formatted("dropShelf.converted", format.title)
                : AppLocalization.string("dropShelf.resized")
        }
    }

    func resizeImage(_ item: DropShelfItem, _ resize: ShelfImageResize) {
        convertImage(item, to: Self.format(keeping: item), resize: resize)
    }

    /// Zips the selection, or every item when nothing is selected.
    func zipItems() {
        let targets = selectedItems.isEmpty ? items : selectedItems
        guard !targets.isEmpty, let urls = try? exporter.draggingURLs(for: targets) else {
            NSSound.beep()
            return
        }

        let name = targets.count == 1
            ? (targets[0].displayName as NSString).deletingPathExtension
            : AppLocalization.string("dropShelf.archiveName")
        let processor = processor

        runProcessing(after: targets.last) {
            try [processor.zip(urls, archiveName: name)]
        } message: { urls in
            AppLocalization.formatted("dropShelf.zipped", urls.first?.lastPathComponent ?? name)
        }
    }

    private func runProcessing(
        after item: DropShelfItem?,
        work: @escaping @Sendable () throws -> [URL],
        message: @escaping ([URL]) -> String
    ) {
        guard !isProcessing else { return }
        isProcessing = true

        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result { try work() }
            }.value

            guard let self else { return }
            isProcessing = false

            switch result {
            case .success(let urls):
                insertProcessedFiles(urls, after: item)
                showToast(message(urls))
            case .failure:
                NSSound.beep()
                showToast(AppLocalization.string("dropShelf.processingFailed"), systemImage: "exclamationmark.triangle.fill")
            }
        }
    }

    /// Resizing keeps a lossy source lossy (JPEG/HEIC) and everything else PNG.
    private static func format(keeping item: DropShelfItem) -> ShelfImageFormat {
        switch item.fileURL?.pathExtension.lowercased() {
        case "jpg", "jpeg": .jpeg
        case "heic", "heif": .heic
        default: .png
        }
    }
}
