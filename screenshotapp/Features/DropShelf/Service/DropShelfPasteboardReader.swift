import AppKit
import Foundation

enum DropShelfPasteboardReader {
    static let supportedPasteboardTypes: [NSPasteboard.PasteboardType] = [
        .fileURL,
        .URL,
        .string,
        .png,
        .tiff,
        NSPasteboard.PasteboardType("public.html")
    ]

    static func items(from pasteboard: NSPasteboard) -> [DropShelfItem] {
        var items: [DropShelfItem] = []
        var seenFileURLs = Set<URL>()
        var seenURLStrings = Set<String>()

        for url in readURLs(from: pasteboard, fileURLsOnly: true) {
            guard seenFileURLs.insert(url).inserted else {
                continue
            }

            items.append(fileItem(for: url))
        }

        for url in readURLs(from: pasteboard, fileURLsOnly: false) where !url.isFileURL {
            guard seenURLStrings.insert(url.absoluteString).inserted else {
                continue
            }

            items.append(linkItem(for: url))
        }

        if items.isEmpty {
            let images = readImages(from: pasteboard)
            for (index, image) in images.enumerated() {
                items.append(
                    DropShelfItem(
                        kind: .image,
                        displayName: "Image \(index + 1)",
                        image: image
                    )
                )
            }
        }

        if let htmlImageURL = imageURLFromHTMLPasteboard(pasteboard),
           seenURLStrings.insert(htmlImageURL.absoluteString).inserted {
            items.append(linkItem(for: htmlImageURL, fallbackName: "Web Image"))
        }

        if let string = pasteboard.string(forType: .string) {
            addStringItem(
                string,
                to: &items,
                seenURLStrings: &seenURLStrings
            )
        }

        return items
    }

    private static func readURLs(from pasteboard: NSPasteboard, fileURLsOnly: Bool) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: fileURLsOnly
        ]

        return (pasteboard.readObjects(forClasses: [NSURL.self], options: options) ?? [])
            .compactMap { object in
                if let url = object as? URL {
                    return url
                }

                if let url = object as? NSURL {
                    return url as URL
                }

                return nil
            }
    }

    private static func readImages(from pasteboard: NSPasteboard) -> [NSImage] {
        let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) ?? []

        if let typedImages = images as? [NSImage], !typedImages.isEmpty {
            return typedImages
        }

        if let image = NSImage(pasteboard: pasteboard) {
            return [image]
        }

        return []
    }

    private static func fileItem(for url: URL) -> DropShelfItem {
        DropShelfItem(
            kind: url.hasDirectoryPath ? .folder : .file,
            displayName: url.lastPathComponent,
            fileURL: url
        )
    }

    private static func linkItem(for url: URL, fallbackName: String? = nil) -> DropShelfItem {
        let name = fallbackName
            ?? url.lastPathComponent.nilIfEmpty
            ?? url.host(percentEncoded: false)
            ?? "Link"

        return DropShelfItem(
            kind: .link,
            displayName: name,
            url: url
        )
    }

    private static func addStringItem(
        _ string: String,
        to items: inout [DropShelfItem],
        seenURLStrings: inout Set<String>
    ) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        if let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(),
           ["http", "https", "file"].contains(scheme) {
            if seenURLStrings.insert(url.absoluteString).inserted {
                items.append(linkItem(for: url))
            }

            return
        }

        let firstLine = trimmed.components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty

        items.append(
            DropShelfItem(
                kind: .text,
                displayName: firstLine ?? "Text Snippet",
                text: trimmed
            )
        )
    }

    private static func imageURLFromHTMLPasteboard(_ pasteboard: NSPasteboard) -> URL? {
        guard let html = pasteboard.string(forType: NSPasteboard.PasteboardType("public.html")) else {
            return nil
        }

        let pattern = #"<img[^>]+src=["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(
                in: html,
                range: NSRange(html.startIndex..<html.endIndex, in: html)
              ),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: html) else {
            return nil
        }

        return URL(string: String(html[range]))
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
