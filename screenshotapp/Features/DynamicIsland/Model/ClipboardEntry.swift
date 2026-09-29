import AppKit

/// One copied item. Kept in memory only; the history never touches disk.
struct ClipboardEntry: Identifiable, Equatable {
    enum Content: Equatable {
        case text(String)
        case url(URL)
        case files([URL])
        case image(NSImage)

        static func == (lhs: Content, rhs: Content) -> Bool {
            switch (lhs, rhs) {
            case let (.text(left), .text(right)): left == right
            case let (.url(left), .url(right)): left == right
            case let (.files(left), .files(right)): left == right
            case let (.image(left), .image(right)): left === right
            default: false
            }
        }
    }

    let id = UUID()
    let content: Content
    let copiedAt: Date
    /// App that was frontmost when the copy happened.
    let sourceBundleIdentifier: String?

    var isImage: Bool {
        if case .image = content { return true }
        return false
    }
}
