import AppKit
import Foundation

enum DynamicIslandNotificationStyle: Equatable {
    case info
    case success
    case warning
    case error
    case media
    case battery
    case system
}

struct DynamicIslandNotification: Identifiable {
    let id = UUID()
    let date = Date()
    /// Small caption above the title, e.g. the posting app's name.
    var caption: String?
    let title: String
    let message: String?
    let systemImage: String
    let style: DynamicIslandNotificationStyle
    /// Optional artwork (e.g. album cover) shown instead of the symbol.
    var image: NSImage?
    /// Optional progress in 0...1 (e.g. battery level).
    var progress: Double?
    /// Identifies the track a media banner belongs to, so late artwork can patch it.
    var mediaKey: String?
    /// App to open when the banner is clicked.
    var sourceAppURL: URL?
}

/// What the island is currently showing; drives size and content.
enum DynamicIslandMode: Equatable {
    case idle
    case compactMedia
    case compactTimer
    case notification
    case expanded
}

/// Hardware notch (or simulated notch) metrics of the screen hosting the island.
struct DynamicIslandGeometry: Equatable {
    let notchSize: CGSize
    let hasNotch: Bool

    static let fallback = DynamicIslandGeometry(notchSize: CGSize(width: 190, height: 32), hasNotch: false)
}
