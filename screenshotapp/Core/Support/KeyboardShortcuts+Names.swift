import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    nonisolated static let captureSelectedArea = Self(
        "captureSelectedArea",
        default: .init(.two, modifiers: [.command, .shift])
    )

    nonisolated static let openDropShelf = Self(
        "openDropShelf",
        default: .init(.d, modifiers: [.command, .shift])
    )
}
