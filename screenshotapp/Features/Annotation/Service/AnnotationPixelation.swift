import AppKit

/// Builds the mosaic used by the Blur tool: the whole image shrunk to a
/// coarse grid, drawn back without interpolation inside each blur rectangle.
/// Pixelating (instead of a Gaussian blur) keeps redacted text unrecoverable.
enum AnnotationPixelation {
    /// Number of mosaic cells along the image's longer side.
    static let cellsOnLongSide: CGFloat = 70

    static func gridSize(forPixelSize size: CGSize) -> CGSize {
        let longSide = max(size.width, size.height)
        guard longSide > 0 else { return .zero }
        let cell = max(longSide / cellsOnLongSide, 6)
        return CGSize(width: max((size.width / cell).rounded(), 1), height: max((size.height / cell).rounded(), 1))
    }

    static func mosaic(of image: NSImage) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let grid = gridSize(forPixelSize: CGSize(width: cgImage.width, height: cgImage.height))
        guard grid.width > 0,
              let context = CGContext(
                data: nil,
                width: Int(grid.width),
                height: Int(grid.height),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(origin: .zero, size: grid))
        guard let small = context.makeImage() else { return nil }
        return NSImage(cgImage: small, size: image.size)
    }
}
