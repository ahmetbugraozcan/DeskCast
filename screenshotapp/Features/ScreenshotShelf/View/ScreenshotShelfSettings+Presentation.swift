import Foundation

// Localized display titles live in the presentation layer so the model enums
// stay free of AppLocalization.

extension PreviewPosition {
    var title: String {
        switch self {
        case .bottomLeft: AppLocalization.string("Bottom Left")
        case .bottomRight: AppLocalization.string("Bottom Right")
        case .topLeft: AppLocalization.string("Top Left")
        case .topRight: AppLocalization.string("Top Right")
        }
    }
}

extension StackDirection {
    var title: String {
        switch self {
        case .horizontal: AppLocalization.string("Horizontal")
        case .vertical: AppLocalization.string("Vertical")
        }
    }
}

extension ShelfThumbnailSize {
    var title: String {
        switch self {
        case .small: AppLocalization.string("Small")
        case .medium: AppLocalization.string("Medium")
        case .large: AppLocalization.string("Large")
        case .custom: AppLocalization.string("Custom")
        }
    }
}

extension ShelfThumbnailAspectRatio {
    var title: String {
        switch self {
        case .ratio16x9: "16:9"
        case .ratio16x10: "16:10"
        case .ratio3x2: "3:2"
        case .ratio4x3: "4:3"
        case .square: AppLocalization.string("Square")
        case .custom: AppLocalization.string("Custom")
        }
    }
}
