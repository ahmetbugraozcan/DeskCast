import CoreGraphics
import Testing
@testable import screenshotapp

/// Synthetic "page": deterministic gray bars of varying width, like lines of
/// text, on a white background. Frames are windows onto it at scroll offsets.
private enum SyntheticPage {
    static let width = 120

    static func pixels(height: Int, seed: Int = 7) -> [UInt8] {
        var generator = seed
        func next() -> Int {
            generator = (generator &* 1_103_515_245 &+ 12_345) & 0x7fffffff
            return generator
        }
        var pixels = [UInt8](repeating: 255, count: width * height)
        var row = 4
        while row < height - 10 {
            let lineHeight = 6 + next() % 6
            let length = 20 + next() % (width - 30)
            let shade = UInt8(20 + next() % 120)
            for line in row..<min(row + lineHeight, height) {
                for column in 5..<(5 + length) { pixels[line * width + column] = shade }
            }
            row += lineHeight + 4 + next() % 10
        }
        return pixels
    }

    static func image(_ pixels: [UInt8], height: Int) -> CGImage? {
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        for index in 0..<(width * height) {
            rgba[index * 4] = pixels[index]
            rgba[index * 4 + 1] = pixels[index]
            rgba[index * 4 + 2] = pixels[index]
        }
        return rgba.withUnsafeMutableBytes { buffer in
            CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )?.makeImage()
        }
    }

    /// A frame showing page rows `top..<top+height`, optionally with fixed
    /// header/footer rows painted over it.
    static func frame(page: [UInt8], top: Int, height: Int, header: Int = 0, footer: Int = 0) -> CGImage? {
        var rows = Array(page[(top * width)..<((top + height) * width)])
        for index in 0..<(header * width) { rows[index] = index % 7 == 0 ? 0 : 90 }
        for index in ((height - footer) * width)..<(height * width) where footer > 0 {
            rows[index] = index % 5 == 0 ? 10 : 160
        }
        return image(rows, height: height)
    }

    /// Grayscale rows of a stitched image, for comparison with the page.
    static func grayRows(_ image: CGImage) -> [UInt8] {
        var rgba = [UInt8](repeating: 0, count: image.width * image.height * 4)
        rgba.withUnsafeMutableBytes { buffer in
            CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return stride(from: 0, to: rgba.count, by: 4).map { rgba[$0] }
    }
}

struct ScrollStitcherTests {
    private let frameHeight = 200

    private func frame(_ page: [UInt8], top: Int, header: Int = 0, footer: Int = 0) throws -> CGImage {
        try #require(SyntheticPage.frame(page: page, top: top, height: frameHeight, header: header, footer: footer))
    }

    private func signature(_ page: [UInt8], top: Int) throws -> [UInt8] {
        try #require(ScrollStitcher.signature(of: try frame(page, top: top)))
    }

    @Test func offsetFinderDetectsScrollAndStillness() throws {
        let page = SyntheticPage.pixels(height: 600)
        let width = ScrollStitcher.signatureWidth
        let before = try signature(page, top: 0)
        let after = try signature(page, top: 37)

        #expect(ScrollOffsetFinder.offset(previous: before, next: after, width: width, height: frameHeight) == 37)
        #expect(ScrollOffsetFinder.offset(previous: before, next: before, width: width, height: frameHeight) == 0)
    }

    @Test func tooFarAScrollLosesTrack() throws {
        let page = SyntheticPage.pixels(height: 800)
        let width = ScrollStitcher.signatureWidth
        let before = try signature(page, top: 0)
        let after = try signature(page, top: 400)
        #expect(ScrollOffsetFinder.offset(previous: before, next: after, width: width, height: frameHeight) == nil)
    }

    @Test func stitchedImageMatchesThePage() throws {
        let pageHeight = 700
        let page = SyntheticPage.pixels(height: pageHeight)
        let first = try frame(page, top: 0)
        var stitcher = try #require(ScrollStitcher(firstFrame: first))

        var results: [ScrollStitcher.AddResult] = []
        for top in [0, 45, 45, 120, 190, 260, 330, 400, 470, pageHeight - frameHeight] {
            let next = try frame(page, top: top)
            results.append(stitcher.add(next))
        }

        #expect(results.contains(.unchanged))
        #expect(!results.contains(.lostTrack))
        #expect(stitcher.height == pageHeight)
        let stitched = try #require(stitcher.makeImage())
        #expect(SyntheticPage.grayRows(stitched) == page)
    }

    @Test func fixedFooterAppearsOnce() throws {
        let page = SyntheticPage.pixels(height: 600)
        let footer = 24
        let first = try frame(page, top: 0, footer: footer)
        var stitcher = try #require(ScrollStitcher(firstFrame: first))
        for top in [60, 120, 180] {
            let next = try frame(page, top: top, footer: footer)
            #expect(stitcher.add(next) != .lostTrack)
        }

        // Page rows 0..<(180 + 200 - 24) followed by one copy of the footer.
        try #require(stitcher.height == 180 + frameHeight)
        let stitched = try #require(stitcher.makeImage())
        let rows = SyntheticPage.grayRows(stitched)
        let contentRows = 180 + frameHeight - footer
        #expect(Array(rows[0..<(contentRows * SyntheticPage.width)]) == Array(page[0..<(contentRows * SyntheticPage.width)]))
    }

    @Test func fixedHeaderDoesNotBreakTracking() throws {
        let page = SyntheticPage.pixels(height: 600)
        let header = 30
        let first = try frame(page, top: 0, header: header)
        var stitcher = try #require(ScrollStitcher(firstFrame: first))
        let next = try frame(page, top: 50, header: header)
        let result = stitcher.add(next)
        #expect(result == .appended(rows: 50))
    }

    @Test func stopsAtTheHeightLimit() throws {
        let page = SyntheticPage.pixels(height: 600)
        let first = try frame(page, top: 0)
        var stitcher = try #require(ScrollStitcher(firstFrame: first, maxHeight: 260))
        let next = try frame(page, top: 100)
        #expect(stitcher.add(next) == .reachedLimit)
        #expect(stitcher.height == 260)
    }
}
