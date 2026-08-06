import Foundation

enum ToastStyle: Equatable {
    case success
    case warning
    case error

    var systemImage: String {
        switch self {
        case .success:
            "checkmark.circle.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        case .error:
            "xmark.circle.fill"
        }
    }

    static func inferred(from systemImage: String) -> ToastStyle {
        let normalizedImage = systemImage.lowercased()

        if normalizedImage.contains("xmark") || normalizedImage.contains("exclamation") {
            return .error
        }

        if normalizedImage.contains("info") {
            return .warning
        }

        return .success
    }
}

/// Presents transient toast messages. Injected so view models don't own AppKit
/// panels (and can be faked in tests).
@MainActor
protocol ToastPresenting: AnyObject {
    func show(_ message: String, systemImage: String)
}

extension ToastPresenting {
    func show(_ message: String) {
        show(message, style: .success)
    }

    func show(_ message: String, style: ToastStyle) {
        show(message, systemImage: style.systemImage)
    }
}

@MainActor
final class ToastPresenter: ToastPresenting {
    private let controller = ToastPanelController()

    func show(_ message: String, systemImage: String) {
        controller.show(
            message: message,
            systemImage: systemImage,
            style: .inferred(from: systemImage)
        )
    }
}
