import CoreGraphics
import ScreenCaptureKit

nonisolated enum ScrollingCaptureError: Error {
    case displayUnavailable
}

/// Captures one area of one display repeatedly, leaving DeskCast's own
/// windows (the outline and the control panel) out of the picture.
nonisolated protocol ScrollingFrameSource: Sendable {
    func captureFrame() async throws -> CGImage
}

nonisolated protocol ScrollingFrameCapturing: Sendable {
    /// `rect` is display-local, in points, with a top-left origin.
    func makeSource(displayID: CGDirectDisplayID, rect: CGRect, scale: CGFloat) async throws -> ScrollingFrameSource
}

nonisolated struct ScrollingFrameCaptureService: ScrollingFrameCapturing {
    func makeSource(displayID: CGDirectDisplayID, rect: CGRect, scale: CGFloat) async throws -> ScrollingFrameSource {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw ScrollingCaptureError.displayUnavailable
        }

        let ownBundleID = Bundle.main.bundleIdentifier
        let filter = SCContentFilter(
            display: display,
            excludingApplications: content.applications.filter { $0.bundleIdentifier == ownBundleID },
            exceptingWindows: []
        )
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = rect
        configuration.width = Int((rect.width * scale).rounded())
        configuration.height = Int((rect.height * scale).rounded())
        configuration.showsCursor = false
        configuration.capturesAudio = false
        return ScreenshotFrameSource(filter: filter, configuration: configuration)
    }
}

/// SCContentFilter and SCStreamConfiguration are only read after creation.
nonisolated private final class ScreenshotFrameSource: ScrollingFrameSource, @unchecked Sendable {
    private let filter: SCContentFilter
    private let configuration: SCStreamConfiguration

    init(filter: SCContentFilter, configuration: SCStreamConfiguration) {
        self.filter = filter
        self.configuration = configuration
    }

    func captureFrame() async throws -> CGImage {
        try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }
}
