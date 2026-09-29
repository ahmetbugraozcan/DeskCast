import AVFoundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum VideoEditingError: Error {
    case exportUnavailable
    case noFrames
    case gifWriteFailed
}

nonisolated protocol VideoTrimming: Sendable {
    /// Writes `start…end` of `source` to `destination` without re-encoding.
    func trim(_ source: URL, start: TimeInterval, end: TimeInterval, to destination: URL) async throws
}

nonisolated protocol GIFExporting: Sendable {
    func exportGIF(from source: URL, times: [TimeInterval], preset: GIFExportPreset, to destination: URL) async throws
}

nonisolated struct VideoTrimService: VideoTrimming {
    func trim(_ source: URL, start: TimeInterval, end: TimeInterval, to destination: URL) async throws {
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw VideoEditingError.exportUnavailable
        }

        let timescale: CMTimeScale = 600
        session.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: timescale),
            end: CMTime(seconds: end, preferredTimescale: timescale)
        )
        do {
            try await session.export(to: destination, as: .mov)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }
}

nonisolated struct GIFExportService: GIFExporting {
    func exportGIF(from source: URL, times: [TimeInterval], preset: GIFExportPreset, to destination: URL) async throws {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: source))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: preset.maxPixelWidth, height: preset.maxPixelWidth * 4)
        let tolerance = CMTime(seconds: 0.5 / preset.framesPerSecond, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        guard let output = CGImageDestinationCreateWithURL(
            destination as CFURL, UTType.gif.identifier as CFString, times.count, nil
        ) else {
            throw VideoEditingError.gifWriteFailed
        }

        CGImageDestinationSetProperties(output, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ] as CFDictionary)
        let frameProperties = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: 1 / preset.framesPerSecond,
                kCGImagePropertyGIFUnclampedDelayTime: 1 / preset.framesPerSecond
            ]
        ] as CFDictionary

        // The destination expects exactly `times.count` frames, so a frame that
        // fails to decode repeats the previous one instead of being skipped.
        var frameCount = 0
        var lastImage: CGImage?
        let cmTimes = times.map { CMTime(seconds: $0, preferredTimescale: 600) }
        for await result in generator.images(for: cmTimes) {
            if Task.isCancelled { break }
            guard let image = (try? result.image) ?? lastImage else { continue }
            CGImageDestinationAddImage(output, image, frameProperties)
            lastImage = image
            frameCount += 1
        }

        guard !Task.isCancelled, let lastImage else {
            try? FileManager.default.removeItem(at: destination)
            throw Task.isCancelled ? CancellationError() : VideoEditingError.noFrames
        }
        while frameCount < times.count {
            CGImageDestinationAddImage(output, lastImage, frameProperties)
            frameCount += 1
        }
        guard CGImageDestinationFinalize(output) else {
            try? FileManager.default.removeItem(at: destination)
            throw VideoEditingError.gifWriteFailed
        }
    }
}
