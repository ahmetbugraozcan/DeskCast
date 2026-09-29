#if DEBUG
import AppKit

/// Debug builds only: `-DeskCastSnapshotDir <folder>` writes a PNG of every
/// visible DeskCast window a few seconds after launch. Works while the screen
/// is locked (unlike `screencapture`), which makes UI checks scriptable.
@MainActor
enum DebugWindowSnapshot {
    static func writeIfRequested() async {
        guard let folder = UserDefaults.standard.string(forKey: "DeskCastSnapshotDir") else { return }

        try? await Task.sleep(for: .seconds(2.5))
        let directory = URL(fileURLWithPath: folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for (index, window) in NSApp.windows.enumerated() where window.isVisible {
            guard let view = window.contentView?.superview ?? window.contentView,
                  let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }

            view.cacheDisplay(in: view.bounds, to: bitmap)
            let name = window.title.isEmpty ? "window-\(index)" : window.title.replacingOccurrences(of: "/", with: "-")
            try? bitmap.representation(using: .png, properties: [:])?
                .write(to: directory.appendingPathComponent("\(name).png"))
        }
    }
}
#endif
