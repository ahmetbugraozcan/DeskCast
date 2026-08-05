import Foundation

// Localized display strings for the drop shelf, kept out of the model layer.

extension DropShelfLayoutMode {
    var title: String {
        switch self {
        case .stack: AppLocalization.string("Stack")
        case .grid: AppLocalization.string("Grid")
        }
    }
}

extension DropShelfItemSize {
    var title: String {
        switch self {
        case .small: AppLocalization.string("Small")
        case .medium: AppLocalization.string("Medium")
        case .large: AppLocalization.string("Large")
        case .custom: AppLocalization.string("Custom")
        }
    }
}

extension DropShelfItemKind {
    var title: String {
        switch self {
        case .file: AppLocalization.string("File")
        case .folder: AppLocalization.string("Folder")
        case .image: AppLocalization.string("Image")
        case .link: AppLocalization.string("Link")
        case .text: AppLocalization.string("Text")
        }
    }
}

extension DropShelfItem {
    var subtitle: String {
        if let fileURL {
            return fileURL.deletingLastPathComponent().path
        }

        if let url {
            return url.host(percentEncoded: false) ?? url.absoluteString
        }

        if let text {
            return text.replacingOccurrences(of: "\n", with: " ")
        }

        return kind.title
    }
}
