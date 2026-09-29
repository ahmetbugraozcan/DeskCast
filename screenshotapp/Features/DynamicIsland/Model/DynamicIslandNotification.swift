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
    var id = UUID()
    var date = Date()
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
    /// Optional button on the banner (e.g. "Join" for a meeting link).
    var action: DynamicIslandNotificationAction?
    /// A quick confirmation (e.g. "Saved to DeskCast") shown in the closed
    /// island's wings instead of a full banner.
    var isCompact = false
    /// What a compact peek says, when not its message or title.
    var peekText: String?

    /// The same alert as a short peek in the closed island's wings.
    func asPeek(showing text: String) -> DynamicIslandNotification {
        var peek = self
        peek.isCompact = true
        peek.peekText = text
        peek.action = nil
        return peek
    }
}

struct DynamicIslandNotificationAction: Equatable {
    let title: String
    let systemImage: String
    let url: URL
}

/// What the island is currently showing; drives size and content.
enum DynamicIslandMode: Equatable {
    case idle
    case compactMedia
    case compactTimer
    case compactBattery
    case compactWeather
    /// The next calendar event (idle content).
    case compactEvent
    /// Claude's 5-hour plan limit (idle content).
    case compactClaude
    case compactFocus
    case compactAgent
    case compactToast
    case notification
    case expanded

    /// The closed island showing something beside the camera.
    var isCompact: Bool {
        switch self {
        case .compactMedia, .compactTimer, .compactBattery, .compactWeather, .compactEvent, .compactClaude, .compactFocus,
             .compactAgent, .compactToast: true
        case .idle, .notification, .expanded: false
        }
    }
}

/// Direction of a trackpad swipe (finger movement) over the island.
enum IslandSwipeDirection: Equatable {
    case up
    case down
    case left
    case right
}

/// Hardware notch (or simulated notch) metrics of the screen hosting the island.
struct DynamicIslandGeometry: Equatable {
    let notchSize: CGSize
    let hasNotch: Bool

    static let fallback = DynamicIslandGeometry(notchSize: CGSize(width: 190, height: 32), hasNotch: false)
}
