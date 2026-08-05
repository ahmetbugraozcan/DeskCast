import AppKit
import UniformTypeIdentifiers

@MainActor
protocol ScreenshotExporting {
    func save(_ image: NSImage, to directoryURL: URL, suggestedFilename: String) throws -> URL
    func save(_ image: NSImage, suggestedFilename: String) throws -> URL?
}

@MainActor
struct ScreenshotExportService: ScreenshotExporting {
    func save(
        _ image: NSImage,
        to directoryURL: URL,
        suggestedFilename: String
    ) throws -> URL {
        guard let pngData = image.tinyShotShelfPNGData else {
            throw CocoaError(.fileWriteUnknown)
        }

        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let url = Self.uniqueDestinationURL(
            in: directoryURL,
            suggestedFilename: suggestedFilename
        )
        try pngData.write(to: url, options: .atomic)
        return url
    }

    func save(
        _ image: NSImage,
        suggestedFilename: String
    ) throws -> URL? {
        guard let pngData = image.tinyShotShelfPNGData else {
            throw CocoaError(.fileWriteUnknown)
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = suggestedFilename

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        try pngData.write(to: url, options: .atomic)
        return url
    }

    private static func uniqueDestinationURL(
        in directoryURL: URL,
        suggestedFilename: String
    ) -> URL {
        let filename = suggestedFilename.isEmpty ? "screenshot.png" : suggestedFilename
        let baseURL = directoryURL.appendingPathComponent(filename)

        guard FileManager.default.fileExists(atPath: baseURL.path) else {
            return baseURL
        }

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
