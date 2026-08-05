import Foundation

enum ImageSearchIndexState: Equatable {
    case pending
    case scanning
    case indexed
    case failed
}

struct ImageSearchItem: Identifiable {
    let url: URL
    var recognizedText: String?
    var indexState: ImageSearchIndexState = .pending

    var id: URL {
        url
    }

    var filename: String {
        url.lastPathComponent
    }
}

struct ImageSearchMatch {
    let item: ImageSearchItem
    let matchedFilename: Bool
    let matchedText: Bool
    let textSnippet: String?
}
