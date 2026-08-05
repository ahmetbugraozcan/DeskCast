import Foundation

/// Presents transient toast messages. Injected so view models don't own AppKit
/// panels (and can be faked in tests).
@MainActor
protocol ToastPresenting: AnyObject {
    func show(_ message: String, systemImage: String)
}

extension ToastPresenting {
    func show(_ message: String) {
        show(message, systemImage: "checkmark.circle.fill")
    }
}

@MainActor
final class ToastPresenter: ToastPresenting {
    private let controller = ToastPanelController()

    func show(_ message: String, systemImage: String) {
        controller.show(message: message, systemImage: systemImage)
    }
}
