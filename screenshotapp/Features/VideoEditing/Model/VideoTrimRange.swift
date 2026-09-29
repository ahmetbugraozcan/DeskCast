import Foundation

/// The kept part of a video, in seconds. Handles can't cross and always keep
/// at least `minimumLength` between them.
nonisolated struct VideoTrimRange: Equatable, Sendable {
    static let minimumLength: TimeInterval = 0.5

    let duration: TimeInterval
    private(set) var start: TimeInterval
    private(set) var end: TimeInterval

    init(duration: TimeInterval) {
        self.duration = max(duration, 0)
        start = 0
        end = self.duration
    }

    var length: TimeInterval { end - start }
    var isFullLength: Bool { start <= 0.001 && end >= duration - 0.001 }

    mutating func setStart(_ value: TimeInterval) {
        start = min(max(value, 0), max(end - Self.minimumLength, 0))
    }

    mutating func setEnd(_ value: TimeInterval) {
        end = max(min(value, duration), min(start + Self.minimumLength, duration))
    }

    /// Keeps playback inside the range.
    func clampedPlayhead(_ time: TimeInterval) -> TimeInterval {
        min(max(time, start), end)
    }

    static func timeText(_ seconds: TimeInterval) -> String {
        let tenths = Int((max(seconds, 0) * 10).rounded())
        return String(format: "%d:%02d.%d", tenths / 600, tenths / 10 % 60, tenths % 10)
    }
}

/// GIF size/smoothness presets; larger ones produce much bigger files.
nonisolated enum GIFExportPreset: String, CaseIterable, Identifiable, Sendable {
    case small, medium, large

    var id: String { rawValue }

    var maxPixelWidth: CGFloat {
        switch self {
        case .small: 480
        case .medium: 720
        case .large: 1080
        }
    }

    var framesPerSecond: Double {
        switch self {
        case .small: 10
        case .medium: 15
        case .large: 20
        }
    }

    var titleKey: String { "videoEdit.gif.\(rawValue)" }

    /// Hard cap so a long range can't produce a GIF of thousands of frames.
    static let maxFrameCount = 600

    /// Frame timestamps sampled evenly across the range at the preset's rate.
    func frameTimes(from start: TimeInterval, to end: TimeInterval) -> [TimeInterval] {
        let length = max(end - start, 0)
        let count = min(max(Int((length * framesPerSecond).rounded(.down)), 1), Self.maxFrameCount)
        let step = length / Double(count)
        return (0..<count).map { start + Double($0) * step }
    }
}

/// Names for files written next to the source video, never overwriting one.
nonisolated enum VideoEditOutputNaming {
    static func url(nextTo source: URL, suffix: String, pathExtension: String, fileManager: FileManager = .default) -> URL {
        let directory = source.deletingLastPathComponent()
        let name = source.deletingPathExtension().lastPathComponent
        let base = suffix.isEmpty ? name : "\(name) \(suffix)"
        var candidate = directory.appendingPathComponent(base).appendingPathExtension(pathExtension)
        var index = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) \(index)").appendingPathExtension(pathExtension)
            index += 1
        }
        return candidate
    }
}
