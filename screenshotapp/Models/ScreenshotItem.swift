import AppKit
import Foundation

struct ScreenshotItem: Identifiable, Equatable {
    let id = UUID()
    let image: NSImage
    let createdAt = Date()
    var isPinned: Bool
    /// Location on disk once the screenshot has been saved (auto-save, quick save,
    /// export, or Save As). Used to reveal the file in Finder.
    var fileURL: URL?

    static func == (lhs: ScreenshotItem, rhs: ScreenshotItem) -> Bool {
        lhs.id == rhs.id
    }
}
