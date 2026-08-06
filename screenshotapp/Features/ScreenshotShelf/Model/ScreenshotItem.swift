import AppKit
import Foundation

enum CaptureShelfMediaKind: Equatable {
    case image
    case video
}

struct ScreenshotItem: Identifiable, Equatable {
    let id = UUID()
    let kind: CaptureShelfMediaKind
    /// Image content for screenshots and a generated poster frame for videos.
    let image: NSImage
    let createdAt = Date()
    var isPinned: Bool
    let durationSeconds: TimeInterval?
    /// Location on disk once the screenshot has been saved (auto-save, quick save,
    /// export, or Save As). Used to reveal the file in Finder.
    var fileURL: URL?

    init(
        image: NSImage,
        isPinned: Bool,
        fileURL: URL? = nil
    ) {
        kind = .image
        self.image = image
        self.isPinned = isPinned
        durationSeconds = nil
        self.fileURL = fileURL
    }

    init(
        videoThumbnail: NSImage,
        durationSeconds: TimeInterval?,
        fileURL: URL,
        isPinned: Bool
    ) {
        kind = .video
        image = videoThumbnail
        self.isPinned = isPinned
        self.durationSeconds = durationSeconds
        self.fileURL = fileURL
    }

    var isVideo: Bool {
        kind == .video
    }

    static func == (lhs: ScreenshotItem, rhs: ScreenshotItem) -> Bool {
        lhs.id == rhs.id
    }
}
