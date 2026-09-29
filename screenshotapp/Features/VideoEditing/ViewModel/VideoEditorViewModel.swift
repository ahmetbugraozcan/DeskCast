import AppKit
import AVFoundation
import Combine

/// Callbacks into the shelf once an export finishes.
struct VideoEditorResultHandlers {
    let trimmed: (URL) -> Void
    let gifExported: (URL) -> Void
    let failed: (String) -> Void
}

/// Drives one Trim / GIF window: playback looped inside the kept range,
/// the range handles, a filmstrip, and the two exports.
@MainActor
final class VideoEditorViewModel: ObservableObject {
    enum Operation: Equatable {
        case trimming
        case exportingGIF
    }

    let source: URL
    let player: AVPlayer

    @Published private(set) var range = VideoTrimRange(duration: 0)
    @Published private(set) var playhead: TimeInterval = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var filmstrip: [NSImage] = []
    @Published private(set) var operation: Operation?
    @Published var gifPreset: GIFExportPreset = .medium

    /// Closes the window once the trimmed video has been saved.
    var onFinished: (() -> Void)?

    private let trimmer: VideoTrimming
    private let gifExporter: GIFExporting
    private let handlers: VideoEditorResultHandlers
    private var timeObserver: Any?
    private var work: Task<Void, Never>?

    static let filmstripFrameCount = 10

    init(source: URL, trimmer: VideoTrimming, gifExporter: GIFExporting, handlers: VideoEditorResultHandlers) {
        self.source = source
        self.trimmer = trimmer
        self.gifExporter = gifExporter
        self.handlers = handlers
        player = AVPlayer(url: source)
        player.actionAtItemEnd = .pause

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated { self?.playerDidAdvance(to: time.seconds) }
        }

        Task { [weak self] in await self?.loadAsset() }
    }

    var isBusy: Bool { operation != nil }
    var canTrim: Bool { !isBusy && range.duration > 0 && !range.isFullLength }
    var canExportGIF: Bool { !isBusy && range.duration > 0 }

    // MARK: - Playback

    func togglePlayback() {
        if isPlaying {
            player.pause()
            isPlaying = false
            return
        }
        if playhead >= range.end - 0.05 || playhead < range.start {
            seek(to: range.start)
        }
        player.play()
        isPlaying = true
    }

    func seek(to seconds: TimeInterval) {
        let target = range.clampedPlayhead(seconds)
        playhead = target
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    func setStart(_ seconds: TimeInterval) {
        pause()
        range.setStart(seconds)
        seek(to: range.start)
    }

    func setEnd(_ seconds: TimeInterval) {
        pause()
        range.setEnd(seconds)
        seek(to: range.end)
    }

    private func pause() {
        player.pause()
        isPlaying = false
    }

    /// Loops playback inside the kept range.
    private func playerDidAdvance(to seconds: TimeInterval) {
        guard seconds.isFinite else { return }
        playhead = seconds
        if isPlaying, seconds >= range.end {
            seek(to: range.start)
            player.play()
        }
    }

    // MARK: - Export

    func saveTrimmedVideo() {
        guard canTrim else { return }
        let destination = VideoEditOutputNaming.url(
            nextTo: source, suffix: AppLocalization.string("videoEdit.trimmedSuffix"), pathExtension: "mov"
        )
        let (source, start, end, trimmer) = (source, range.start, range.end, trimmer)
        run(.trimming, failure: "videoEdit.trim.failed", closesWindow: true) {
            try await trimmer.trim(source, start: start, end: end, to: destination)
        } success: { [handlers] in
            handlers.trimmed(destination)
        }
    }

    func exportGIF() {
        guard canExportGIF else { return }
        let destination = VideoEditOutputNaming.url(nextTo: source, suffix: "", pathExtension: "gif")
        let preset = gifPreset
        let times = preset.frameTimes(from: range.start, to: range.end)
        let (source, gifExporter) = (source, gifExporter)
        // The window stays open so another size (or a trim) can follow.
        run(.exportingGIF, failure: "videoEdit.gif.failed", closesWindow: false) {
            try await gifExporter.exportGIF(from: source, times: times, preset: preset, to: destination)
        } success: { [handlers] in
            handlers.gifExported(destination)
        }
    }

    /// Stops playback and any export; called when the window closes.
    func stop() {
        work?.cancel()
        player.pause()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }

    private func run(
        _ operation: Operation,
        failure: String,
        closesWindow: Bool,
        _ body: @escaping @Sendable () async throws -> Void,
        success: @escaping () -> Void
    ) {
        pause()
        self.operation = operation
        work = Task { [weak self] in
            do {
                try await body()
                guard !Task.isCancelled else { return }
                self?.operation = nil
                success()
                if closesWindow { self?.onFinished?() }
            } catch {
                self?.operation = nil
                if !(error is CancellationError), !Task.isCancelled {
                    self?.handlers.failed(AppLocalization.string(failure))
                }
            }
        }
    }

    // MARK: - Loading

    private func loadAsset() async {
        let asset = AVURLAsset(url: source)
        guard let duration = try? await asset.load(.duration), duration.seconds.isFinite else { return }
        range = VideoTrimRange(duration: duration.seconds)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 240, height: 240)
        let count = Self.filmstripFrameCount
        let times = (0..<count).map { index in
            CMTime(seconds: duration.seconds * (Double(index) + 0.5) / Double(count), preferredTimescale: 600)
        }
        var frames: [NSImage] = []
        for await result in generator.images(for: times) {
            guard let image = try? result.image else { continue }
            frames.append(NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height)))
        }
        filmstrip = frames
    }
}
