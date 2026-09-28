import AppKit

/// Media players DeskCast can read and control. macOS offers no public API for
/// the system-wide "Now Playing" session, so each supported player is driven
/// through its own scripting dictionary and playback notifications.
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

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    var appIcon: NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }

        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

enum MediaCommand: Sendable {
    case togglePlayPause
    case nextTrack
    case previousTrack
}

/// Raw track state read from a player script; produced off the main actor.
nonisolated struct MediaPlayerTrackSnapshot: Sendable {
    let player: MediaPlayerApp
    let trackID: String
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let elapsed: TimeInterval
    let isPlaying: Bool
    let artworkURL: URL?
}

struct NowPlayingInfo {
    let player: MediaPlayerApp
    let trackID: String
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let elapsed: TimeInterval
    /// When `elapsed` was read, so the UI can extrapolate the position while playing.
    let capturedAt: Date
    let isPlaying: Bool
    var artwork: NSImage?
    /// Dominant artwork color, used to tint the equalizer and progress bar.
    var artworkTint: NSColor?

    init(
        snapshot: MediaPlayerTrackSnapshot,
        capturedAt: Date = Date(),
        artwork: NSImage? = nil,
        artworkTint: NSColor? = nil
    ) {
        player = snapshot.player
        trackID = snapshot.trackID
        title = snapshot.title
        artist = snapshot.artist
        album = snapshot.album
        duration = max(snapshot.duration, 0)
        elapsed = max(snapshot.elapsed, 0)
        self.capturedAt = capturedAt
        isPlaying = snapshot.isPlaying
        self.artwork = artwork
        self.artworkTint = artworkTint
    }

    var cacheKey: String { "\(player.rawValue)|\(trackID)" }

    func isSameTrack(as other: NowPlayingInfo?) -> Bool {
        guard let other else { return false }
        return other.player == player && other.trackID == trackID
    }

    func elapsed(at date: Date) -> TimeInterval {
        let value = isPlaying ? elapsed + date.timeIntervalSince(capturedAt) : elapsed
        return duration > 0 ? min(value, duration) : value
    }

    func progress(at date: Date) -> Double {
        guard duration > 0 else { return 0 }
        return min(max(elapsed(at: date) / duration, 0), 1)
    }

    /// Returns a copy with the playing flag flipped immediately, so controls feel
    /// responsive before the player confirms the change.
    func togglingPlayback(at date: Date = Date()) -> NowPlayingInfo {
        let snapshot = MediaPlayerTrackSnapshot(
            player: player,
            trackID: trackID,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            elapsed: elapsed(at: date),
            isPlaying: !isPlaying,
            artworkURL: nil
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
