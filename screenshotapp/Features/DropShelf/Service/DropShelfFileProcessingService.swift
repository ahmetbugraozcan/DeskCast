import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Image formats the shelf can convert to.
nonisolated enum ShelfImageFormat: String, CaseIterable, Identifiable, Sendable {
    case png
    case jpeg
    case heic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPEG"
        case .heic: "HEIC"
        }
    }

    var utType: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        case .heic: .heic
        }
    }

    var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        case .heic: "heic"
        }
    }
}

/// How the shelf shrinks an image; the result never grows past the source.
nonisolated enum ShelfImageResize: CaseIterable, Identifiable, Sendable {
    case half
    case maxEdge1920
    case maxEdge1280
    case maxEdge640

    var id: Self { self }

    /// Longest edge (pixels) of the result for a source with this longest edge.
    func targetMaxEdge(forSourceMaxEdge sourceMaxEdge: Int) -> Int {
        let target: Int
        switch self {
        case .half: target = sourceMaxEdge / 2
        case .maxEdge1920: target = 1920
        case .maxEdge1280: target = 1280
        case .maxEdge640: target = 640
        }
        return max(1, min(target, sourceMaxEdge))
    }

    /// Filename suffix, e.g. `photo-1280.jpg`.
    var filenameSuffix: String {
        switch self {
        case .half: "50%"
        case .maxEdge1920: "1920"
        case .maxEdge1280: "1280"
        case .maxEdge640: "640"
        }
    }
}

nonisolated enum DropShelfProcessingError: Error {
    case unreadableImage
    case writeFailed
    case zipFailed
}

nonisolated protocol DropShelfFileProcessing: Sendable {
    /// Writes a converted (and optionally resized) copy of the image at
    /// `sourceURL` and returns the new file's URL. The source is untouched.
    func convertImage(at sourceURL: URL, to format: ShelfImageFormat, resize: ShelfImageResize?) throws -> URL
    /// Zips the files and folders into `<archiveName>.zip` and returns its URL.
    func zip(_ fileURLs: [URL], archiveName: String) throws -> URL
}

/// Runs off the main thread; results land in a DeskCast temporary folder that
/// the shelf's items point at, like dragged-in files.
nonisolated struct DropShelfFileProcessingService: DropShelfFileProcessing {
    private static let jpegQuality = 0.85

    func convertImage(at sourceURL: URL, to format: ShelfImageFormat, resize: ShelfImageResize?) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
            throw DropShelfProcessingError.unreadableImage
        }

        let image: CGImage?
        if let resize {
            let sourceMaxEdge = Self.maxEdge(of: source)
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: resize.targetMaxEdge(forSourceMaxEdge: sourceMaxEdge)
            ]
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        } else {
            image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        }

        guard let image else { throw DropShelfProcessingError.unreadableImage }

        let stem = sourceURL.deletingPathExtension().lastPathComponent
        let name = resize.map { "\(stem)-\($0.filenameSuffix)" } ?? stem
        let destinationURL = try Self.outputDirectory().appendingPathComponent("\(name).\(format.fileExtension)")

        guard let destination = CGImageDestinationCreateWithURL(
            destinationURL as CFURL,
            format.utType.identifier as CFString,
            1,
            nil
        ) else {
            throw DropShelfProcessingError.writeFailed
        }

        let properties: [CFString: Any] = format == .png ? [:] : [kCGImageDestinationLossyCompressionQuality: Self.jpegQuality]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else { throw DropShelfProcessingError.writeFailed }
        return destinationURL
    }

    func zip(_ fileURLs: [URL], archiveName: String) throws -> URL {
        guard !fileURLs.isEmpty else { throw DropShelfProcessingError.zipFailed }

        let fileManager = FileManager.default
        let workDirectory = try Self.outputDirectory()
        let staging = workDirectory.appendingPathComponent(archiveName, isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)

        var usedNames = Set<String>()
        for url in fileURLs {
            let name = Self.uniqueName(url.lastPathComponent, taken: &usedNames)
            try fileManager.copyItem(at: url, to: staging.appendingPathComponent(name))
        }

        let archiveURL = workDirectory.appendingPathComponent("\(archiveName).zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        // Finder's "Compress" format: keeps the folder, drops resource forks.
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", staging.path, archiveURL.path]
        try process.run()
        process.waitUntilExit()

        try? fileManager.removeItem(at: staging)

        guard process.terminationStatus == 0, fileManager.fileExists(atPath: archiveURL.path) else {
            throw DropShelfProcessingError.zipFailed
        }

        return archiveURL
    }

    private static func maxEdge(of source: CGImageSource) -> Int {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        return max(width, height, 1)
    }

    /// A fresh folder per result, so names never collide with earlier results.
    private static func outputDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeskCast-Processed", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func uniqueName(_ name: String, taken: inout Set<String>) -> String {
        var candidate = name
        let stem = (name as NSString).deletingPathExtension
        let pathExtension = (name as NSString).pathExtension
        var index = 2

        while taken.contains(candidate.lowercased()) {
            candidate = pathExtension.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(pathExtension)"
            index += 1
        }

        taken.insert(candidate.lowercased())
        return candidate
    }
}
