import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

@MainActor
protocol ScreenRecordingServicing: AnyObject {
    func start(
        _ request: ScreenRecordingRequest,
        completion: @escaping (Result<Void, ScreenRecordingServiceError>) -> Void
    )
    func stop(
        completion: @escaping (Result<URL, ScreenRecordingServiceError>) -> Void
    )
}

@MainActor
final class ScreenCaptureRecordingService: NSObject, ScreenRecordingServicing {
    private var stream: SCStream?
    private var writer: ScreenRecordingWriter?
    private var stopCompletion: ((Result<URL, ScreenRecordingServiceError>) -> Void)?
    private var didFinish = false
    private let sampleQueue = DispatchQueue(label: "com.ahmetbugraozcan.screenshotapp.recording.samples")

    func start(
        _ request: ScreenRecordingRequest,
        completion: @escaping (Result<Void, ScreenRecordingServiceError>) -> Void
    ) {
        guard stream == nil else {
            completion(.failure(.alreadyRecording))
            return
        }

        Task { @MainActor in
            do {
                try FileManager.default.createDirectory(
                    at: request.destinationURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )

                let content = try await SCShareableContent.excludingDesktopWindows(
                    false,
                    onScreenWindowsOnly: false
                )
                guard let display = content.displays.first(where: { $0.displayID == request.display.id }) else {
                    completion(.failure(.displayUnavailable))
                    return
                }

                let ownBundleID = Bundle.main.bundleIdentifier
                let excludedApplications = content.applications.filter {
                    $0.bundleIdentifier == ownBundleID
                }
                let filter = SCContentFilter(
                    display: display,
                    excludingApplications: excludedApplications,
                    exceptingWindows: []
                )
                let dimensions = Self.pixelDimensions(for: request, display: display)
                let configuration = Self.streamConfiguration(
                    for: request,
                    display: display,
                    dimensions: dimensions
                )
                let stream = SCStream(filter: filter, configuration: configuration, delegate: self)

                let writer = try ScreenRecordingWriter(
                    outputURL: request.destinationURL,
                    videoSettings: Self.videoSettings(dimensions: dimensions, request: request),
                    capturesSystemAudio: request.capturesSystemAudio,
                    capturesMicrophone: request.capturesMicrophone,
                    queue: sampleQueue
                )

                try stream.addStreamOutput(writer, type: .screen, sampleHandlerQueue: sampleQueue)
                if request.capturesSystemAudio {
                    try stream.addStreamOutput(writer, type: .audio, sampleHandlerQueue: sampleQueue)
                }
                if request.capturesMicrophone {
                    try stream.addStreamOutput(writer, type: .microphone, sampleHandlerQueue: sampleQueue)
                }

                writer.startWriting()

                self.stream = stream
                self.writer = writer
                didFinish = false

                try await stream.startCapture()
                completion(.success(()))
            } catch {
                writer?.cancel()
                resetState()
                completion(.failure(.captureFailed(error.localizedDescription)))
            }
        }
    }

    func stop(
        completion: @escaping (Result<URL, ScreenRecordingServiceError>) -> Void
    ) {
        guard let stream, let writer else {
            completion(.failure(.notRecording))
            return
        }

        stopCompletion = completion
        Task { @MainActor in
            try? await stream.stopCapture()
            writer.finish { [weak self] result in
                Task { @MainActor in
                    self?.handleWriterFinish(result)
                }
            }
        }
    }

    private func handleWriterFinish(_ result: Result<URL, Error>) {
        guard !didFinish else { return }
        didFinish = true
        let completion = stopCompletion
        resetState()

        switch result {
        case .success(let url):
            guard FileManager.default.fileExists(atPath: url.path) else {
                completion?(.failure(.captureFailed("The recording file was not created.")))
                return
            }
            completion?(.success(url))
        case .failure(let error):
            completion?(.failure(.captureFailed(error.localizedDescription)))
        }
    }

    // MARK: - Configuration

    private static func pixelDimensions(
        for request: ScreenRecordingRequest,
        display: SCDisplay
    ) -> (width: Int, height: Int) {
        let sourceRect = request.sourceRect ?? CGRect(
            x: 0,
            y: 0,
            width: display.frame.width,
            height: display.frame.height
        )
        let horizontalScale = CGFloat(display.width) / max(display.frame.width, 1)
        let verticalScale = CGFloat(display.height) / max(display.frame.height, 1)

        return (
            evenPixelDimension(sourceRect.width * horizontalScale),
            evenPixelDimension(sourceRect.height * verticalScale)
        )
    }

    private static func streamConfiguration(
        for request: ScreenRecordingRequest,
        display: SCDisplay,
        dimensions: (width: Int, height: Int)
    ) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        if let sourceRect = request.sourceRect {
            configuration.sourceRect = sourceRect
        }

        configuration.width = dimensions.width
        configuration.height = dimensions.height
        configuration.minimumFrameInterval = CMTime(
            value: 1,
            timescale: CMTimeScale(max(request.frameRate, 1))
        )
        configuration.queueDepth = 6
        configuration.showsCursor = request.showsCursor
        configuration.showMouseClicks = request.showsMouseClicks
        configuration.capturesAudio = request.capturesSystemAudio
        configuration.excludesCurrentProcessAudio = true
        configuration.captureMicrophone = request.capturesMicrophone
        configuration.microphoneCaptureDeviceID = request.microphoneDeviceID
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.streamName = AppConstants.appName

        return configuration
    }

    private static func videoSettings(
        dimensions: (width: Int, height: Int),
        request: ScreenRecordingRequest
    ) -> [String: Any] {
        let codec: AVVideoCodecType = request.codec == .hevc ? .hevc : .h264
        let bitrate = targetBitrate(dimensions: dimensions, request: request)
        let fps = max(request.frameRate, 1)

        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: bitrate,
            AVVideoMaxKeyFrameIntervalKey: fps * 2,
            AVVideoExpectedSourceFrameRateKey: fps,
            AVVideoAllowFrameReorderingKey: false
        ]
        if request.codec == .h264 {
            compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
        }

        return [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: dimensions.width,
            AVVideoHeightKey: dimensions.height,
            AVVideoCompressionPropertiesKey: compression
        ]
    }

    private static func targetBitrate(
        dimensions: (width: Int, height: Int),
        request: ScreenRecordingRequest
    ) -> Int {
        let pixels = Double(dimensions.width * dimensions.height)
        let fps = Double(max(request.frameRate, 1))
        let bppf = request.quality.bitsPerPixelPerFrame(codec: request.codec)
        let raw = pixels * fps * bppf
        return Int(min(max(raw, 1_000_000), 150_000_000))
    }

    private static func evenPixelDimension(_ value: CGFloat) -> Int {
        let roundedValue = max(Int(value.rounded()), 2)
        return roundedValue.isMultiple(of: 2) ? roundedValue : roundedValue - 1
    }

    private func resetState() {
        stream = nil
        writer = nil
        stopCompletion = nil
    }
}

extension ScreenCaptureRecordingService: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, let writer else { return }
            writer.finish { [weak self] result in
                Task { @MainActor in
                    switch result {
                    case .success(let url):
                        self?.handleWriterFinish(.success(url))
                    case .failure:
                        self?.handleWriterFinish(.failure(error))
                    }
                }
            }
        }
    }
}

/// Owns the `AVAssetWriter` and consumes `SCStream` sample buffers on a dedicated
/// serial queue, giving explicit control over codec, bitrate and keyframe interval
/// (which `SCRecordingOutput` does not expose).
private final class ScreenRecordingWriter: NSObject, SCStreamOutput {
    private enum WriterError: Error {
        case cannotAddVideoInput
        case notWriting
    }

    private let queue: DispatchQueue
    private let assetWriter: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let systemAudioInput: AVAssetWriterInput?
    private let microphoneInput: AVAssetWriterInput?
    private var hasSession = false
    private var isFinished = false

    init(
        outputURL: URL,
        videoSettings: [String: Any],
        capturesSystemAudio: Bool,
        capturesMicrophone: Bool,
        queue: DispatchQueue
    ) throws {
        self.queue = queue
        assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true

        let systemAudioInput = capturesSystemAudio ? Self.makeAudioInput() : nil
        let microphoneInput = capturesMicrophone ? Self.makeAudioInput() : nil
        self.systemAudioInput = systemAudioInput
        self.microphoneInput = microphoneInput

        super.init()

        guard assetWriter.canAdd(videoInput) else {
            throw WriterError.cannotAddVideoInput
        }
        assetWriter.add(videoInput)

        if let systemAudioInput, assetWriter.canAdd(systemAudioInput) {
            assetWriter.add(systemAudioInput)
        }
        if let microphoneInput, assetWriter.canAdd(microphoneInput) {
            assetWriter.add(microphoneInput)
        }
    }

    private static func makeAudioInput() -> AVAssetWriterInput {
        // ScreenCaptureKit delivers float PCM, which a .mov container cannot accept
        // as passthrough; encode to AAC so the writer transcodes it for us.
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 160_000
        ]
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        return input
    }

    func startWriting() {
        queue.async { [self] in
            assetWriter.startWriting()
        }
    }

    func finish(completion: @escaping (Result<URL, Error>) -> Void) {
        queue.async { [self] in
            guard !isFinished else { return }
            isFinished = true

            guard assetWriter.status == .writing else {
                completion(.failure(assetWriter.error ?? WriterError.notWriting))
                return
            }

            videoInput.markAsFinished()
            systemAudioInput?.markAsFinished()
            microphoneInput?.markAsFinished()

            let outputURL = assetWriter.outputURL
            assetWriter.finishWriting { [self] in
                if let error = assetWriter.error {
                    completion(.failure(error))
                } else {
                    completion(.success(outputURL))
                }
            }
        }
    }

    func cancel() {
        queue.async { [self] in
            guard !isFinished else { return }
            isFinished = true
            if assetWriter.status == .writing {
                assetWriter.cancelWriting()
            }
        }
    }

    // MARK: - SCStreamOutput

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard !isFinished, CMSampleBufferDataIsReady(sampleBuffer) else { return }
        guard assetWriter.status == .writing || assetWriter.status == .unknown else { return }

        switch type {
        case .screen:
            guard isCompleteFrame(sampleBuffer) else { return }
            if !hasSession {
                assetWriter.startSession(
                    atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                )
                hasSession = true
            }
            if videoInput.isReadyForMoreMediaData {
                videoInput.append(sampleBuffer)
            }
        case .audio:
            guard hasSession, let input = systemAudioInput, input.isReadyForMoreMediaData else { return }
            input.append(sampleBuffer)
        case .microphone:
            guard hasSession, let input = microphoneInput, input.isReadyForMoreMediaData else { return }
            input.append(sampleBuffer)
        @unknown default:
            break
        }
    }

    private func isCompleteFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: false
        ) as? [[SCStreamFrameInfo: Any]],
            let statusRawValue = attachments.first?[.status] as? Int,
            let status = SCFrameStatus(rawValue: statusRawValue) else {
            return false
        }
        return status == .complete
    }
}
