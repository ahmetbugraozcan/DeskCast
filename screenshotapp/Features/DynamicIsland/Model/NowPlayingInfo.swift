import AppKit

/// Media players DeskCast drives through their scripting dictionaries (track
/// details, artwork, the player's own volume). Everything else — browsers,
/// Podcasts, … — comes from the system now playing session instead.
enum MediaPlayerApp: String, CaseIterable, Identifiable, Sendable {
    case music
    case spotify

    nonisolated var id: String { rawValue }

    nonisolated var bundleIdentifier: String {
        switch self {
        case .music: "com.apple.Music"
        case .spotify: "com.spotify.client"
        }
    }

    /// Product names are brand names and stay untranslated.
    nonisolated var displayName: String {
        switch self {
        case .music: "Music"
        case .spotify: "Spotify"
        }
    }

    /// Distributed notification each player posts when its track or state changes.
    nonisolated var playbackChangedNotification: Notification.Name {
        switch self {
        case .music: Notification.Name("com.apple.Music.playerInfo")
        case .spotify: Notification.Name("com.spotify.client.PlaybackStateChanged")
        }
    }

    nonisolated init?(bundleIdentifier: String) {
        guard let player = Self.allCases.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            return nil
        }
        self = player
    }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    var appIcon: NSImage? {
        NowPlayingSource(player: self).appIcon
    }
}

/// The app that owns a now playing session: a scripted player, or any app the
/// system now playing session reports (Safari, Chrome, Podcasts, …).
nonisolated struct NowPlayingSource: Hashable, Sendable {
    let bundleIdentifier: String

    init(bundleIdentifier: String) {
        self.bundleIdentifier = bundleIdentifier
    }

    init(player: MediaPlayerApp) {
        bundleIdentifier = player.bundleIdentifier
    }

    /// Set when DeskCast can script this app directly.
    var player: MediaPlayerApp? {
        MediaPlayerApp(bundleIdentifier: bundleIdentifier)
    }

    @MainActor
    var displayName: String {
        if let player {
            return player.displayName
        }

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return bundleIdentifier
        }

        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    @MainActor
    var appIcon: NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }

        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

enum MediaCommand: Sendable {
    /// Explicit play/pause rather than a toggle, so a stale reading can't
    /// make the button do the opposite of what it shows.
    case play
    case pause
    case nextTrack
    case previousTrack
}

/// Raw track state read from a player script or the system session; produced
/// off the main actor.
nonisolated struct MediaPlayerTrackSnapshot: Sendable {
    let source: NowPlayingSource
    let trackID: String
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let elapsed: TimeInterval
    let isPlaying: Bool
    let artworkURL: URL?
    /// Cover bytes delivered with the state (system session only).
    let artworkData: Data?
    /// The player's own volume (0...1), when it exposes one.
    let volume: Double?
    /// What the session accepts; a single web video has no next/previous.
    let capabilities: NowPlayingCapabilities

    init(
        source: NowPlayingSource,
        trackID: String,
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval,
        elapsed: TimeInterval,
        isPlaying: Bool,
        artworkURL: URL?,
        artworkData: Data? = nil,
        volume: Double? = nil,
        capabilities: NowPlayingCapabilities = .all
    ) {
        self.source = source
        self.trackID = trackID
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.elapsed = elapsed
        self.isPlaying = isPlaying
        self.artworkURL = artworkURL
        self.artworkData = artworkData
        self.volume = volume
        self.capabilities = capabilities
    }

    init(
        player: MediaPlayerApp,
        trackID: String,
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval,
        elapsed: TimeInterval,
        isPlaying: Bool,
        artworkURL: URL?,
        volume: Double? = nil
    ) {
        self.init(
            source: NowPlayingSource(player: player),
            trackID: trackID,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            elapsed: elapsed,
            isPlaying: isPlaying,
            artworkURL: artworkURL,
            volume: volume
        )
    }
}

nonisolated struct NowPlayingCapabilities: Equatable, Sendable {
    var canSkip: Bool
    var canGoBack: Bool
    var canSeek: Bool

    static let all = NowPlayingCapabilities(canSkip: true, canGoBack: true, canSeek: true)
}

struct NowPlayingInfo {
    let source: NowPlayingSource
    let trackID: String
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let elapsed: TimeInterval
    /// When `elapsed` was read, so the UI can extrapolate the position while playing.
    let capturedAt: Date
    let isPlaying: Bool
    /// The player's own volume (0...1); `nil` when only the system volume applies.
    var volume: Double?
    let capabilities: NowPlayingCapabilities
    var artwork: NSImage?
    /// Dominant artwork color, used to tint the equalizer and progress bar.
    var artworkTint: NSColor?

    init(
        snapshot: MediaPlayerTrackSnapshot,
        capturedAt: Date = Date(),
        artwork: NSImage? = nil,
        artworkTint: NSColor? = nil
    ) {
        source = snapshot.source
        trackID = snapshot.trackID
        title = snapshot.title
        artist = snapshot.artist
        album = snapshot.album
        duration = max(snapshot.duration, 0)
        elapsed = max(snapshot.elapsed, 0)
        self.capturedAt = capturedAt
        isPlaying = snapshot.isPlaying
        volume = snapshot.volume.map { min(max($0, 0), 1) }
        capabilities = snapshot.capabilities
        self.artwork = artwork
        self.artworkTint = artworkTint
    }

    /// Scripted player, when DeskCast can control this source directly.
    var player: MediaPlayerApp? { source.player }

    var cacheKey: String { "\(source.bundleIdentifier)|\(trackID)" }

    func isSameTrack(as other: NowPlayingInfo?) -> Bool {
        guard let other else { return false }
        return other.source == source && other.trackID == trackID
    }

    func elapsed(at date: Date) -> TimeInterval {
        let value = isPlaying ? elapsed + date.timeIntervalSince(capturedAt) : elapsed
        return duration > 0 ? min(value, duration) : value
    }

    func progress(at date: Date) -> Double {
        guard duration > 0 else { return 0 }
        return min(max(elapsed(at: date) / duration, 0), 1)
    }

    /// Returns a copy positioned at `seconds`, shown until the player confirms.
    func seeking(to seconds: TimeInterval, at date: Date = Date()) -> NowPlayingInfo {
        let snapshot = MediaPlayerTrackSnapshot(
            source: source,
            trackID: trackID,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            elapsed: duration > 0 ? min(max(seconds, 0), duration) : max(seconds, 0),
            isPlaying: isPlaying,
            artworkURL: nil,
            volume: volume,
            capabilities: capabilities
        )
        return NowPlayingInfo(snapshot: snapshot, capturedAt: date, artwork: artwork, artworkTint: artworkTint)
    }

    /// Returns a copy with the playing flag flipped immediately, so controls feel
    /// responsive before the player confirms the change.
    func togglingPlayback(at date: Date = Date()) -> NowPlayingInfo {
        let snapshot = MediaPlayerTrackSnapshot(
            source: source,
            trackID: trackID,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            elapsed: elapsed(at: date),
            isPlaying: !isPlaying,
            artworkURL: nil,
            volume: volume,
            capabilities: capabilities
        )
        return NowPlayingInfo(snapshot: snapshot, capturedAt: date, artwork: artwork, artworkTint: artworkTint)
    }
}

extension NSImage {
    /// Average color of the image, brightened so it reads on the island's black
    /// background. Cheap enough for once-per-track use (renders into 1×1 pixel).
    var islandTintColor: NSColor? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        // The context writes into `pixel`, so it must only live inside this scope.
        let didDraw = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }

            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }

        guard didDraw else { return nil }

        let color = NSColor(
            srgbRed: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1
        )

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        color.usingColorSpace(.sRGB)?.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        return NSColor(
            hue: hue,
            saturation: min(saturation * 1.2, 1),
            brightness: max(brightness, 0.72),
            alpha: 1
        )
    }
}
