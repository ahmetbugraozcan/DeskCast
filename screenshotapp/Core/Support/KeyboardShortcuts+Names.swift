import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    nonisolated static let captureSelectedArea = Self(
        "captureSelectedArea",
        default: .init(.two, modifiers: [.command, .shift])
    )

    nonisolated static let captureVideo = Self("captureVideo")

    nonisolated static let pickColor = Self("pickColor")

    nonisolated static let scrollingCapture = Self("scrollingCapture")

    nonisolated static let openDropShelf = Self(
        "openDropShelf",
        default: .init(.d, modifiers: [.command, .shift])
    )
}
