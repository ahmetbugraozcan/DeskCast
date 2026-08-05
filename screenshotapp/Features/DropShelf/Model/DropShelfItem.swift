import AppKit
import Foundation

enum DropShelfItemKind: String, CaseIterable, Identifiable {
    case file
    case folder
    case image
    case link
    case text

    var id: String { rawValue }

    var title: String {
        switch self {
        case .file: AppLocalization.string("File")
        case .folder: AppLocalization.string("Folder")
        case .image: AppLocalization.string("Image")
        case .link: AppLocalization.string("Link")
        case .text: AppLocalization.string("Text")
        }
    }

    var systemImage: String {
        switch self {
        case .file: "doc"
        case .folder: "folder"
        case .image: "photo"
        case .link: "link"
        case .text: "text.alignleft"
        }
    }
}

struct DropShelfItem: Identifiable, Equatable {
    let id: UUID
    var kind: DropShelfItemKind
    var displayName: String
    var fileURL: URL?
    var url: URL?
    var text: String?
    var image: NSImage?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        kind: DropShelfItemKind,
        displayName: String,
        fileURL: URL? = nil,
        url: URL? = nil,
        text: String? = nil,
        image: NSImage? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.fileURL = fileURL
        self.url = url
        self.text = text
        self.image = image
        self.createdAt = createdAt
    }

    static func == (lhs: DropShelfItem, rhs: DropShelfItem) -> Bool {
        lhs.id == rhs.id
    }

    var isFileBacked: Bool {
        fileURL != nil
    }

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
