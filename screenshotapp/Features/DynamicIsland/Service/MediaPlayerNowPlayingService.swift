import AppKit

/// Reads the playing track from supported players and sends transport commands.
/// Injected into `DynamicIslandViewModel` so the view model never talks to
/// AppleScript or notification centers directly.
@MainActor
protocol NowPlayingProviding: AnyObject {
    var onChange: ((NowPlayingInfo?) -> Void)? { get set }
    func start()
    func stop()
    func refresh()
    func send(_ command: MediaCommand, to player: MediaPlayerApp)
    /// Shows this player's track when several players have one loaded.
    func prefer(_ player: MediaPlayerApp)
}

/// macOS has no public API for the system "Now Playing" session (MediaRemote is
/// entitlement-gated for third-party apps), so this service drives Music and
/// Spotify directly: their distributed playback notifications trigger a refresh,
/// and AppleScript reads track details / artwork and sends play-pause/next/previous.
/// Scripts only run while the player is already running so nothing gets launched.
@MainActor
final class MediaPlayerNowPlayingService: NowPlayingProviding {
    var onChange: ((NowPlayingInfo?) -> Void)?

    private let scriptQueue = DispatchQueue(
        label: "com.ahmetbugraozcan.screenshotapp.nowplaying.scripts",
        qos: .userInitiated
    )
    private var distributedObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var pollTimer: Timer?
    private var pendingRefresh: DispatchWorkItem?
    private var refreshGeneration = 0
    private var current: NowPlayingInfo?
    private var lastActivePlayer: MediaPlayerApp?
    /// Picked in the Now Playing source menu; wins over "whichever is playing".
    private var preferredPlayer: MediaPlayerApp?
    private var artworkCache: [String: (image: NSImage, tint: NSColor?)] = [:]
    private var artworkLoadingKeys: Set<String> = []
    /// Tracks without artwork, so the poll doesn't re-run the artwork script.
    private var artworkUnavailableKeys: Set<String> = []
    private var isStarted = false

    /// Playback notifications cover track/state changes; the poll only corrects
    /// position drift (seeking) and players that post nothing.
    private static let pollInterval: TimeInterval = 6
    private static let artworkCacheLimit = 24

    func start() {
        guard !isStarted else { return }
        isStarted = true

        let distributedCenter = DistributedNotificationCenter.default()
        distributedObservers = MediaPlayerApp.allCases.map { player in
            distributedCenter.addObserver(
                forName: player.playbackChangedNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    // Activity in another player overrides a manual pick.
                    if self?.preferredPlayer != player {
                        self?.preferredPlayer = nil
                    }

                    self?.lastActivePlayer = player
                    self?.scheduleRefresh(after: 0.15)
                }
            }
        }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification
        ].map { name in
            workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let bundleIdentifier = application?.bundleIdentifier

                MainActor.assumeIsolated {
                    guard MediaPlayerApp.allCases.contains(where: { $0.bundleIdentifier == bundleIdentifier }) else {
                        return
                    }

                    // Give a terminating player a moment to leave the running list.
                    self?.scheduleRefresh(after: 1)
                }
            }
        }

        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        refresh()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false

        distributedObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        distributedObservers = []
        workspaceObservers = []
        pollTimer?.invalidate()
        pollTimer = nil
        pendingRefresh?.cancel()
        pendingRefresh = nil
        // Invalidate in-flight reads so a late result can't republish.
        refreshGeneration += 1
        current = nil
    }

    func refresh() {
        pendingRefresh?.cancel()
        pendingRefresh = nil

        guard isStarted else { return }

        let players = MediaPlayerApp.allCases.filter(\.isRunning)

        guard !players.isEmpty else {
            publish(nil)
            return
        }

        refreshGeneration += 1
        let generation = refreshGeneration

        scriptQueue.async { [weak self] in
            let snapshots = players.compactMap { Self.readTrack(from: $0) }

            Task { @MainActor in
                self?.apply(snapshots, generation: generation)
            }
        }
    }

    func send(_ command: MediaCommand, to player: MediaPlayerApp) {
        guard player.isRunning else { return }

        let source = Self.commandScript(command, for: player)
        lastActivePlayer = player

        scriptQueue.async { [weak self] in
            _ = Self.run(source)

            Task { @MainActor in
                self?.scheduleRefresh(after: 0.3)
            }
        }
    }

    func prefer(_ player: MediaPlayerApp) {
        lastActivePlayer = player
        preferredPlayer = player
        refresh()
    }

    private func scheduleRefresh(after delay: TimeInterval) {
        pendingRefresh?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
        pendingRefresh = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func apply(_ snapshots: [MediaPlayerTrackSnapshot], generation: Int) {
        guard isStarted, generation == refreshGeneration else { return }

        // Prefer whatever is audibly playing, then the player that last changed,
        // then the one already on screen.
        let chosen = snapshots.first(where: { $0.player == preferredPlayer })
            ?? snapshots.first(where: \.isPlaying)
            ?? snapshots.first(where: { $0.player == lastActivePlayer })
            ?? snapshots.first(where: { $0.player == current?.player })
            ?? snapshots.first

        guard let chosen else {
            publish(nil)
            return
        }

        var info = NowPlayingInfo(snapshot: chosen)

        if let cached = artworkCache[info.cacheKey] {
            info.artwork = cached.image
            info.artworkTint = cached.tint
            publish(info)
        } else {
            // Keep the previous cover while the same track's artwork is loading.
            if info.isSameTrack(as: current) {
                info.artwork = current?.artwork
                info.artworkTint = current?.artworkTint
            }

            publish(info)
            loadArtwork(for: chosen, key: info.cacheKey)
        }
    }

    private func publish(_ info: NowPlayingInfo?) {
        current = info
        onChange?(info)
    }

    private func loadArtwork(for snapshot: MediaPlayerTrackSnapshot, key: String) {
        guard !artworkLoadingKeys.contains(key), !artworkUnavailableKeys.contains(key) else { return }
        artworkLoadingKeys.insert(key)

        let queue = scriptQueue

        Task { [weak self] in
            let data = await Self.artworkData(for: snapshot, queue: queue)
            guard let self else { return }

            self.artworkLoadingKeys.remove(key)

            guard let data, let image = NSImage(data: data) else {
                self.artworkUnavailableKeys.insert(key)
                return
            }

            if self.artworkCache.count >= Self.artworkCacheLimit {
                self.artworkCache.removeAll()
                self.artworkUnavailableKeys.removeAll()
            }
            let tint = image.islandTintColor
            self.artworkCache[key] = (image, tint)

            guard self.isStarted, var current = self.current, current.cacheKey == key else { return }
            current.artwork = image
            current.artworkTint = tint
            self.publish(current)
        }
    }

    // MARK: - Scripting (runs on `scriptQueue`)

    nonisolated private static func artworkData(
        for snapshot: MediaPlayerTrackSnapshot,
        queue: DispatchQueue
    ) async -> Data? {
        if let url = snapshot.artworkURL {
            return try? await URLSession.shared.data(from: url).0
        }

        guard snapshot.player == .music else { return nil }

        return await withCheckedContinuation { continuation in
            queue.async {
                let data = run(musicArtworkScript)?.data
                continuation.resume(returning: data?.isEmpty == false ? data : nil)
            }
        }
    }

    nonisolated private static func readTrack(from player: MediaPlayerApp) -> MediaPlayerTrackSnapshot? {
        // Reads a list instead of a joined string so numbers never go through a
        // locale-dependent text coercion (e.g. "3,5" in Turkish).
        guard let list = run(trackScript(for: player)), list.numberOfItems >= 8 else {
            return nil
        }

        func text(_ index: Int) -> String {
            list.atIndex(index)?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        func number(_ index: Int) -> Double {
            let value = list.atIndex(index)?.doubleValue ?? 0
            return value.isFinite ? value : 0
        }

        let title = text(3)
        let artist = text(4)

        guard !title.isEmpty || !artist.isEmpty else { return nil }

        let trackID = text(2)
        let artworkURLString = text(8)

        return MediaPlayerTrackSnapshot(
            player: player,
            trackID: trackID.isEmpty ? "\(title)|\(artist)" : trackID,
            title: title,
            artist: artist,
            album: text(5),
            duration: number(6),
            elapsed: number(7),
            isPlaying: list.atIndex(1)?.booleanValue ?? false,
            artworkURL: artworkURLString.isEmpty ? nil : URL(string: artworkURLString)
        )
    }

    nonisolated private static func run(_ source: String) -> NSAppleEventDescriptor? {
        guard let script = NSAppleScript(source: source) else { return nil }

        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        return errorInfo == nil ? result : nil
    }

    /// Returns `{isPlaying, id, title, artist, album, durationSeconds, positionSeconds, artworkURL}`
    /// or `{}` when nothing is loaded.
    nonisolated private static func trackScript(for player: MediaPlayerApp) -> String {
        switch player {
        case .music:
            """
            tell application id "\(player.bundleIdentifier)"
                try
                    if player state is stopped then return {}
                    set trackRef to current track
                    set isPlaying to (player state is playing)
                    set trackPosition to 0
                    try
                        set trackPosition to player position
                    end try
                    return {isPlaying, persistent ID of trackRef, name of trackRef, artist of trackRef, album of trackRef, duration of trackRef, trackPosition, ""}
                on error
                    return {}
                end try
            end tell
            """
        case .spotify:
            """
            tell application id "\(player.bundleIdentifier)"
                try
                    if player state is stopped then return {}
                    set trackRef to current track
                    set isPlaying to (player state is playing)
                    set artURL to ""
                    try
                        set artURL to artwork url of trackRef
                    end try
                    return {isPlaying, id of trackRef, name of trackRef, artist of trackRef, album of trackRef, (duration of trackRef) / 1000, player position, artURL}
                on error
                    return {}
                end try
            end tell
            """
        }
    }

    nonisolated private static let musicArtworkScript = """
    tell application id "com.apple.Music"
        try
            return raw data of artwork 1 of current track
        on error
            try
                return data of artwork 1 of current track
            on error
                return missing value
            end try
        end try
    end tell
    """

    nonisolated private static func commandScript(_ command: MediaCommand, for player: MediaPlayerApp) -> String {
        let verb = switch command {
        case .togglePlayPause: "playpause"
        case .nextTrack: "next track"
        case .previousTrack: "previous track"
        }

        return "tell application id \"\(player.bundleIdentifier)\" to \(verb)"
    }
}
