import AppKit

/// Cross-feature contract that lets the screenshot shelf hand a capture off to the
/// drop shelf without depending on its concrete view model. Implemented by
/// `DropShelfViewModel` and injected via the composition root.
@MainActor
protocol ShelfCollecting: AnyObject {
    func addScreenshot(_ image: NSImage, name: String)
}
