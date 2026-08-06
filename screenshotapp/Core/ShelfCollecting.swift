import AppKit

/// Cross-feature contract that lets the screenshot shelf hand a capture off to the
/// drop shelf without depending on its concrete view model. Implemented by
/// `DropShelfViewModel` and injected via the composition root.
@MainActor
protocol ShelfCollecting: AnyObject {
    func addScreenshot(_ image: NSImage, name: String)
    func addFile(_ url: URL)
}

/// Cross-feature boundary used by Screen Recording to place a finished movie
/// into the same floating capture shelf as screenshots.
@MainActor
protocol VideoShelfCollecting: AnyObject {
    func addVideo(at url: URL)
}
