import AppKit
import ImageIO
import Testing
@testable import screenshotapp

struct DropShelfProcessingTests {
    private let service = DropShelfFileProcessingService()

    private func makePNG(width: Int, height: Int) throws -> URL {
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ))
        let data = try #require(rep.representation(using: .png, properties: [:]))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("shelf-test-\(UUID().uuidString).png")
        try data.write(to: url)
        return url
    }

    private func pixelSize(of url: URL) throws -> (width: Int, height: Int) {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        return (properties[kCGImagePropertyPixelWidth] as? Int ?? 0, properties[kCGImagePropertyPixelHeight] as? Int ?? 0)
    }

    @Test func convertsPNGToJPEG() throws {
        let source = try makePNG(width: 40, height: 20)
        let output = try service.convertImage(at: source, to: .jpeg, resize: nil)

        #expect(output.pathExtension == "jpg")
        #expect(try pixelSize(of: output) == (40, 20))
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test func resizesByHalfAndNeverUpscales() throws {
        let source = try makePNG(width: 400, height: 200)

        let half = try service.convertImage(at: source, to: .png, resize: .half)
        #expect(try pixelSize(of: half) == (200, 100))
        #expect(half.lastPathComponent.hasSuffix("-50%.png"))

        let capped = try service.convertImage(at: source, to: .png, resize: .maxEdge1920)
        #expect(try pixelSize(of: capped) == (400, 200))
    }

    @Test func zipsFilesIntoOneArchive() throws {
        let first = try makePNG(width: 4, height: 4)
        let second = try makePNG(width: 4, height: 4)

        let archive = try service.zip([first, second], archiveName: "Shelf Test")

        #expect(archive.lastPathComponent == "Shelf Test.zip")
        let size = try FileManager.default.attributesOfItem(atPath: archive.path)[.size] as? Int ?? 0
        #expect(size > 0)
    }

    @Test func uniqueNamesAvoidCollisionsCaseInsensitively() {
        var taken = Set<String>()
        let names = ["a.png", "A.png", "a.png", "b"].map { DropShelfFileProcessingService.uniqueName($0, taken: &taken) }
        #expect(names == ["a.png", "A 2.png", "a 3.png", "b"])
    }

    @Test func resizeTargetsClampToSource() {
        #expect(ShelfImageResize.half.targetMaxEdge(forSourceMaxEdge: 3000) == 1500)
        #expect(ShelfImageResize.maxEdge1280.targetMaxEdge(forSourceMaxEdge: 3000) == 1280)
        #expect(ShelfImageResize.maxEdge1280.targetMaxEdge(forSourceMaxEdge: 800) == 800)
    }
}
