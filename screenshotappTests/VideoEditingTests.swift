import AVFoundation
import ImageIO
import Testing
@testable import screenshotapp

struct VideoTrimRangeTests {
    @Test func handlesCannotCrossOrLeaveTheVideo() {
        var range = VideoTrimRange(duration: 10)
        #expect(range.isFullLength)

        range.setStart(-3)
        #expect(range.start == 0)
        range.setEnd(20)
        #expect(range.end == 10)

        range.setStart(9.9)
        #expect(range.start == 10 - VideoTrimRange.minimumLength)
        range.setEnd(0)
        #expect(range.end == range.start + VideoTrimRange.minimumLength)
        #expect(!range.isFullLength)
    }

    @Test func playheadStaysInsideRange() {
        var range = VideoTrimRange(duration: 10)
        range.setStart(2)
        range.setEnd(5)
        #expect(range.clampedPlayhead(1) == 2)
        #expect(range.clampedPlayhead(7) == 5)
        #expect(range.length == 3)
    }

    @Test func timeTextShowsTenths() {
        #expect(VideoTrimRange.timeText(0) == "0:00.0")
        #expect(VideoTrimRange.timeText(75.46) == "1:15.5")
    }

    @Test func gifFrameTimesFollowPresetRate() {
        let times = GIFExportPreset.small.frameTimes(from: 1, to: 3)
        #expect(times.count == 20)
        #expect(times.first == 1)
        #expect(abs((times.last ?? 0) - 2.9) < 0.0001)
        #expect(GIFExportPreset.large.frameTimes(from: 0, to: 600).count == GIFExportPreset.maxFrameCount)
        #expect(GIFExportPreset.medium.frameTimes(from: 0, to: 0.01).count == 1)
    }

    @Test func outputNamesNeverOverwrite() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("clip.mov")

        let first = VideoEditOutputNaming.url(nextTo: source, suffix: "trimmed", pathExtension: "mov")
        #expect(first.lastPathComponent == "clip trimmed.mov")
        try Data().write(to: first)
        let second = VideoEditOutputNaming.url(nextTo: source, suffix: "trimmed", pathExtension: "mov")
        #expect(second.lastPathComponent == "clip trimmed 2.mov")
        #expect(VideoEditOutputNaming.url(nextTo: source, suffix: "", pathExtension: "gif").lastPathComponent == "clip.gif")
    }
}

/// Runs the real AVFoundation/ImageIO services on a tiny generated video.
struct VideoEditingServiceTests {
    private static func makeVideo(seconds: Int, fps: Int32 = 10) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 48
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 48
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        for frame in 0..<(seconds * Int(fps)) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, 64, 48, kCVPixelFormatType_32BGRA, nil, &buffer)
            let pixelBuffer = try #require(buffer)
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            memset(CVPixelBufferGetBaseAddress(pixelBuffer), Int32(frame * 7 % 255), CVPixelBufferGetDataSize(pixelBuffer))
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
        }
        input.markAsFinished()
        await writer.finishWriting()
        return url
    }

    @Test func trimKeepsOnlyTheRange() async throws {
        let source = try await Self.makeVideo(seconds: 3)
        let output = source.deletingPathExtension().appendingPathExtension("trimmed.mov")
        defer { [source, output].forEach { try? FileManager.default.removeItem(at: $0) } }

        try await VideoTrimService().trim(source, start: 1, end: 2, to: output)
        let duration = try await AVURLAsset(url: output).load(.duration).seconds
        #expect(abs(duration - 1) < 0.25)
    }

    @Test func gifHasOneFramePerTimestampAndLoops() async throws {
        let source = try await Self.makeVideo(seconds: 2)
        let output = source.deletingPathExtension().appendingPathExtension("gif")
        defer { [source, output].forEach { try? FileManager.default.removeItem(at: $0) } }

        let times = GIFExportPreset.small.frameTimes(from: 0, to: 1.5)
        try await GIFExportService().exportGIF(from: source, times: times, preset: .small, to: output)

        let gif = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
        #expect(CGImageSourceGetCount(gif) == times.count)
        let properties = CGImageSourceCopyProperties(gif, nil) as? [CFString: Any]
        let gifInfo = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        #expect(gifInfo?[kCGImagePropertyGIFLoopCount] as? Int == 0)
    }
}
