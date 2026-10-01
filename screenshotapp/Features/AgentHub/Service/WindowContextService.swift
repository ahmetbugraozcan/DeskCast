import AppKit
import ScreenCaptureKit

@MainActor
protocol WindowContextProviding {
    /// The window of another app under `point` (AppKit screen coordinates),
    /// with a picture of it and, for browsers, the active tab's address.
    func context(at point: CGPoint) async -> AgentWindowContext?
}

/// Finds the window under a point with the window list, captures it with
/// ScreenCaptureKit (Screen Recording permission; without it the context
/// has no picture) and asks browsers for their URL (Automation).
final class WindowContextService: WindowContextProviding {
    private static let maxImageWidth: CGFloat = 1568

    private static let browserScripts: [String: String] = [
        "com.apple.Safari": "tell application \"Safari\" to return URL of current tab of front window",
        "com.google.Chrome": "tell application \"Google Chrome\" to return URL of active tab of front window",
        "company.thebrowser.Browser": "tell application \"Arc\" to return URL of active tab of front window",
        "com.brave.Browser": "tell application \"Brave Browser\" to return URL of active tab of front window",
        "com.microsoft.edgemac": "tell application \"Microsoft Edge\" to return URL of active tab of front window"
    ]

    func context(at point: CGPoint) async -> AgentWindowContext? {
        guard let info = Self.windowInfo(at: point) else { return nil }
        let app = NSRunningApplication(processIdentifier: info.pid)
        let image = await Self.capture(windowID: info.windowID)
        let url = await Self.browserURL(bundleID: app?.bundleIdentifier)

        return AgentWindowContext(
            appName: app?.localizedName ?? info.owner,
            title: info.title,
            url: url,
            image: image,
            frame: info.frame
        )
    }

    private struct WindowInfo {
        let windowID: CGWindowID
        let pid: pid_t
        let owner: String
        let title: String
        let frame: CGRect
    }

    private static func windowInfo(at point: CGPoint) -> WindowInfo? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let primaryHeight = NSScreen.screens.first?.frame.height else {
            return nil
        }
        // The window list uses a top-left origin on the primary screen.
        let flipped = CGPoint(x: point.x, y: primaryHeight - point.y)
        let ownPID = ProcessInfo.processInfo.processIdentifier

        for window in list {
            guard window[kCGWindowLayer as String] as? Int == 0,
                  let pid = window[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let id = window[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
                  bounds.contains(flipped) else {
                continue
            }
            let frame = CGRect(x: bounds.minX, y: primaryHeight - bounds.maxY, width: bounds.width, height: bounds.height)
            return WindowInfo(
                windowID: id,
                pid: pid,
                owner: window[kCGWindowOwnerName as String] as? String ?? "",
                title: window[kCGWindowName as String] as? String ?? "",
                frame: frame
            )
        }
        return nil
    }

    private static func capture(windowID: CGWindowID) async -> Data? {
        guard CGPreflightScreenCaptureAccess(),
              let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true),
              let window = content.windows.first(where: { $0.windowID == windowID }) else {
            return nil
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        let scale = min(maxImageWidth / max(window.frame.width, 1), 2)
        configuration.width = Int(window.frame.width * scale)
        configuration.height = Int(window.frame.height * scale)
        configuration.showsCursor = false
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) else {
            return nil
        }
        return NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    }

    private static func browserURL(bundleID: String?) async -> String? {
        guard let bundleID, let script = browserScripts[bundleID] else { return nil }

        return await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return nil }
            process.waitUntilExit()
            let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return process.terminationStatus == 0 && text?.isEmpty == false ? text : nil
        }.value
    }
}
