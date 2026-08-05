import AppKit
import Foundation

@MainActor
enum DropShelfExportService {
    static func export(_ items: [DropShelfItem], to directoryURL: URL) throws -> [URL] {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        return try items.map { item in
            try materialize(item, in: directoryURL)
        }
    }

    static func previewURL(for item: DropShelfItem) throws -> URL {
        if let fileURL = item.fileURL {
            return fileURL
        }

        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(AppConstants.appName)-DropShelf", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        return try materialize(item, in: directoryURL)
    }

    static func draggingURLs(for items: [DropShelfItem]) throws -> [URL] {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(AppConstants.appName)-DropShelf-Drag", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        return try items.map { item in
            if let fileURL = item.fileURL {
                return fileURL
            }

            return try materialize(item, in: directoryURL)
        }
    }

    private static func materialize(_ item: DropShelfItem, in directoryURL: URL) throws -> URL {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        if let fileURL = item.fileURL {
            let destinationURL = uniqueDestinationURL(
                in: directoryURL,
                suggestedFilename: fileURL.lastPathComponent
            )
            try FileManager.default.copyItem(at: fileURL, to: destinationURL)
            return destinationURL
        }

        if let image = item.image {
            guard let pngData = image.tinyShotShelfPNGData else {
                throw CocoaError(.fileWriteUnknown)
            }

            let destinationURL = uniqueDestinationURL(
                in: directoryURL,
                suggestedFilename: filename(
                    from: item.displayName,
                    fallbackStem: "image",
                    extensionName: "png"
                )
            )
            try pngData.write(to: destinationURL, options: .atomic)
            return destinationURL
        }

        if let text = item.text {
            let destinationURL = uniqueDestinationURL(
                in: directoryURL,
                suggestedFilename: filename(
                    from: item.displayName,
                    fallbackStem: "text-snippet",
                    extensionName: "txt"
                )
            )
            try text.write(to: destinationURL, atomically: true, encoding: .utf8)
            return destinationURL
        }

        if let url = item.url {
            let destinationURL = uniqueDestinationURL(
                in: directoryURL,
                suggestedFilename: filename(
                    from: item.displayName,
                    fallbackStem: "link",
                    extensionName: "webloc"
                )
            )
            let plist = ["URL": url.absoluteString]
            let data = try PropertyListSerialization.data(
                fromPropertyList: plist,
                format: .xml,
                options: 0
            )
            try data.write(to: destinationURL, options: .atomic)
            return destinationURL
        }

        throw CocoaError(.fileWriteUnknown)
    }

    private static func filename(
        from displayName: String,
        fallbackStem: String,
        extensionName: String
    ) -> String {
        let sanitized = sanitizedFilename(displayName, fallback: fallbackStem)
        let url = URL(fileURLWithPath: sanitized)

        if url.pathExtension.lowercased() == extensionName.lowercased() {
            return sanitized
        }

        let stem = url.deletingPathExtension().lastPathComponent.nilIfEmpty ?? fallbackStem
        return "\(stem).\(extensionName)"
    }

    private static func sanitizedFilename(_ filename: String, fallback: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:")
            .union(.newlines)
        let components = filename
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return components.nilIfEmpty ?? fallback
    }

    private static func uniqueDestinationURL(
        in directoryURL: URL,
        suggestedFilename: String
    ) -> URL {
        let filename = sanitizedFilename(suggestedFilename, fallback: "item")
        let baseURL = directoryURL.appendingPathComponent(filename)

        guard !FileManager.default.fileExists(atPath: baseURL.path) else {
            return numberedDestinationURL(for: baseURL, in: directoryURL)
        }

        return baseURL
    }

    private static func numberedDestinationURL(for baseURL: URL, in directoryURL: URL) -> URL {
        let extensionName = baseURL.pathExtension
        let stem = baseURL.deletingPathExtension().lastPathComponent

        for index in 2... {
            let candidateFilename = extensionName.isEmpty
                ? "\(stem)-\(index)"
                : "\(stem)-\(index).\(extensionName)"
            let candidateURL = directoryURL.appendingPathComponent(candidateFilename)

            if !FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }

        return baseURL
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
