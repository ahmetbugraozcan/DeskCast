import CoreGraphics

/// Finds how far content moved between two frames of the same scrolling area.
///
/// Frames are reduced to grayscale "signatures" (`width` samples per pixel
/// row). For each candidate offset `dy`, row `r` of the new frame should equal
/// row `r + dy` of the previous one. Only rows with some contrast are scored,
/// so blank background can't make every offset look like a match.
nonisolated enum ScrollOffsetFinder {
    /// Mean per-sample difference (0–255) under which two rows count as equal.
    static let rowTolerance = 6
    /// A row needs this much contrast (max − min) to be scored.
    static let informativeContrast: UInt8 = 16
    /// Share of scored rows that must match for an offset to be accepted.
    static let minimumMatchRatio = 0.9
    /// The frames must still overlap by this share of their height.
    static let minimumOverlapRatio = 0.15
    private static let maxSampledRows = 160

    static func rowsMatch(_ lhs: ArraySlice<UInt8>, _ rhs: ArraySlice<UInt8>) -> Bool {
        var total = 0
        for (left, right) in zip(lhs, rhs) {
            total += abs(Int(left) - Int(right))
        }
        return total <= rowTolerance * lhs.count
    }

    private static func rowsMatch(
        _ lhs: UnsafeBufferPointer<UInt8>, _ lhsStart: Int,
        _ rhs: UnsafeBufferPointer<UInt8>, _ rhsStart: Int,
        _ width: Int
    ) -> Bool {
        var total = 0
        let limit = rowTolerance * width
        for column in 0..<width {
            total += abs(Int(lhs[lhsStart + column]) - Int(rhs[rhsStart + column]))
            if total > limit { return false }
        }
        return true
    }

    static func isInformative(_ row: ArraySlice<UInt8>) -> Bool {
        guard let low = row.min(), let high = row.max() else { return false }
        return high - low >= informativeContrast
    }

    /// The downward scroll distance in rows: 0 when nothing moved, nil when
    /// the frames don't overlap enough (or have too little detail) to tell.
    static func offset(previous: [UInt8], next: [UInt8], width: Int, height: Int) -> Int? {
        guard width > 0, height > 1, previous.count == width * height, next.count == width * height else { return nil }

        func row(_ pixels: [UInt8], _ index: Int) -> ArraySlice<UInt8> {
            pixels[(index * width)..<((index + 1) * width)]
        }

        // Fixed header/footer bands don't move with the content; leave them out.
        let bandLimit = height / 4
        let topBand = staticTopRows(previous: previous, next: next, width: width, height: height, limit: bandLimit)
        guard topBand < height else { return 0 }
        let bottomBand = staticBottomRows(previous: previous, next: next, width: width, height: height, limit: bandLimit)
        let scoredRange = topBand..<max(height - bottomBand, topBand)

        let informativeRows = scoredRange.filter { isInformative(row(next, $0)) }
        guard informativeRows.count >= 4 else {
            // Nothing to compare against: unchanged if the frames are equal.
            return (0..<height).allSatisfy { rowsMatch(row(next, $0), row(previous, $0)) } ? 0 : nil
        }

        let minimumOverlap = max(Int(Double(height) * minimumOverlapRatio), 2)
        var best: (dy: Int, ratio: Double)?
        var candidateCount = informativeRows.count

        for dy in 0...(height - minimumOverlap) {
            // Rows sorted ascending: drop those whose partner in the previous
            // frame would fall into its fixed footer or past its bottom.
            while candidateCount > 0, informativeRows[candidateCount - 1] + dy >= scoredRange.upperBound {
                candidateCount -= 1
            }
            guard candidateCount >= 4 else { break }
            let step = max(candidateCount / maxSampledRows, 1)
            let sampleCount = (candidateCount + step - 1) / step
            // Give up on this offset as soon as it can't beat the best so far.
            let allowedMisses = Int(Double(sampleCount) * (1 - max(minimumMatchRatio, best?.ratio ?? 0)))
            var misses = 0
            previous.withUnsafeBufferPointer { before in
                next.withUnsafeBufferPointer { after in
                    for index in stride(from: 0, to: candidateCount, by: step) {
                        let rowIndex = informativeRows[index]
                        if !rowsMatch(after, rowIndex * width, before, (rowIndex + dy) * width, width) {
                            misses += 1
                            if misses > allowedMisses { return }
                        }
                    }
                }
            }
            guard misses <= allowedMisses else { continue }
            let ratio = Double(sampleCount - misses) / Double(sampleCount)
            // Strictly better only: among equal scores the smallest move wins.
            if ratio > (best?.ratio ?? 0) + 0.0001 {
                best = (dy, ratio)
            }
        }

        guard let best, best.ratio >= minimumMatchRatio else { return nil }
        return best.dy
    }

    /// Rows at the top that stayed put (a fixed header), counted while the
    /// rows keep matching. Returns `height` when the frames are identical.
    static func staticTopRows(previous: [UInt8], next: [UInt8], width: Int, height: Int, limit: Int) -> Int {
        var band = 0
        var index = 0
        while index < height {
            let current = next[(index * width)..<((index + 1) * width)]
            let before = previous[(index * width)..<((index + 1) * width)]
            guard rowsMatch(current, before) else { break }
            if isInformative(current) || index == height - 1 { band = index + 1 }
            index += 1
        }
        if index == height { return height }
        return min(band, limit)
    }

    /// Rows at the bottom that stayed put while the content scrolled — a
    /// fixed footer or toolbar that must not be repeated in the stitched image.
    static func staticBottomRows(previous: [UInt8], next: [UInt8], width: Int, height: Int, limit: Int) -> Int {
        var band = 0
        var index = height - 1
        while index >= max(height - limit, 0) {
            let current = next[(index * width)..<((index + 1) * width)]
            let before = previous[(index * width)..<((index + 1) * width)]
            guard rowsMatch(current, before) else { break }
            if isInformative(current) { band = height - index }
            index -= 1
        }
        return band
    }
}

/// Builds one tall image from frames captured while the user scrolls down.
/// Only the newly revealed rows of each frame are kept.
nonisolated struct ScrollStitcher: @unchecked Sendable {
    enum AddResult: Equatable {
        case appended(rows: Int)
        case unchanged
        case lostTrack
        case reachedLimit
    }

    private struct Strip {
        let image: CGImage
        /// Rows of `image` used, from its top.
        var rows: Int
    }

    static let signatureWidth = 64

    let frameWidth: Int
    let frameHeight: Int
    let maxHeight: Int
    private var strips: [Strip]
    private var footer: CGImage?
    private var lastSignature: [UInt8]

    init?(firstFrame: CGImage, maxHeight: Int = 20_000) {
        guard let signature = Self.signature(of: firstFrame) else { return nil }
        frameWidth = firstFrame.width
        frameHeight = firstFrame.height
        self.maxHeight = maxHeight
        strips = [Strip(image: firstFrame, rows: firstFrame.height)]
        lastSignature = signature
    }

    /// Height of the stitched image so far, footer included.
    var height: Int {
        strips.reduce(0) { $0 + $1.rows } + (footer?.height ?? 0)
    }

    mutating func add(_ frame: CGImage) -> AddResult {
        guard frame.width == frameWidth, frame.height == frameHeight,
              let signature = Self.signature(of: frame) else { return .lostTrack }
        guard height < maxHeight else { return .reachedLimit }

        let width = Self.signatureWidth
        guard let dy = ScrollOffsetFinder.offset(
            previous: lastSignature, next: signature, width: width, height: frameHeight
        ) else {
            return .lostTrack
        }
        guard dy > 0 else { return .unchanged }

        let band = ScrollOffsetFinder.staticBottomRows(
            previous: lastSignature, next: signature, width: width, height: frameHeight, limit: frameHeight / 4
        )
        if band > 0, footer == nil, var last = strips.popLast() {
            // The first scroll reveals the fixed footer: cut it from what is
            // already kept and add it back once, at the very end.
            last.rows = max(last.rows - band, 0)
            strips.append(last)
            footer = frame.cropping(to: CGRect(x: 0, y: frameHeight - band, width: frameWidth, height: band))
                .flatMap(Self.copy)
        }

        let footerRows = footer?.height ?? 0
        let newRows = min(dy, frameHeight - footerRows, maxHeight - height)
        guard newRows > 0 else { return .reachedLimit }
        let top = frameHeight - footerRows - newRows
        guard let strip = frame.cropping(to: CGRect(x: 0, y: top, width: frameWidth, height: newRows)).flatMap(Self.copy) else {
            return .lostTrack
        }

        strips.append(Strip(image: strip, rows: newRows))
        lastSignature = signature
        return height >= maxHeight ? .reachedLimit : .appended(rows: newRows)
    }

    func makeImage() -> CGImage? {
        let total = height
        guard total > 0, let context = CGContext(
            data: nil,
            width: frameWidth,
            height: total,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Core Graphics draws bottom-up; walk the strips from the top.
        var top = 0
        for strip in strips + (footer.map { [Strip(image: $0, rows: $0.height)] } ?? []) where strip.rows > 0 {
            guard let part = strip.rows == strip.image.height
                ? strip.image
                : strip.image.cropping(to: CGRect(x: 0, y: 0, width: frameWidth, height: strip.rows)) else { continue }
            context.draw(part, in: CGRect(x: 0, y: total - top - strip.rows, width: frameWidth, height: strip.rows))
            top += strip.rows
        }
        return context.makeImage()
    }

    /// Grayscale, `signatureWidth` samples per pixel row, top row first.
    static func signature(of image: CGImage) -> [UInt8]? {
        let width = signatureWidth
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? pixels : nil
    }

    /// Crops share the source frame's memory; copying keeps only the strip.
    private static func copy(_ image: CGImage) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }
}
