import AppKit

/// Reads the playing track and sends transport commands. Injected into
/// `DynamicIslandViewModel` so the view model never talks to AppleScript, the
/// system session bridge or notification centers directly.
@MainActor
protocol NowPlayingProviding: AnyObject {
    var onChange: ((NowPlayingInfo?) -> Void)? { get set }
    func start()
    func stop()
    func refresh()
    func send(_ command: MediaCommand, to source: NowPlayingSource)
    func seek(to seconds: TimeInterval, in source: NowPlayingSource)
    /// Sets a scripted player's own volume (0...1).
    func setVolume(_ volume: Double, for player: MediaPlayerApp)
    /// Shows this player's track when several players have one loaded.
    func prefer(_ player: MediaPlayerApp)
}

/// Combines two sources:
/// - the system now playing session (`SystemNowPlayingBridge`), which covers
///   every app that reports to Control Center — browsers/YouTube included;
/// - Music and Spotify through AppleScript, which adds what the system session
///   lacks (the player's own volume, Spotify track ids for "Up Next") and keeps
///   working if the bridge can't run.
/// Scripts only run while the player is already running so nothing gets launched.
@MainActor
final class MediaPlayerNowPlayingService: NowPlayingProviding {
    var onChange: ((NowPlayingInfo?) -> Void)?

    private let scriptQueue = DispatchQueue(
        label: "com.ahmetbugraozcan.screenshotapp.nowplaying.scripts",
        qos: .userInitiated
    )
    private let systemBridge: SystemNowPlayingBridge
    private var distributedObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var pollTimer: Timer?
    private var pendingRefresh: DispatchWorkItem?
    private var refreshGeneration = 0
    private var current: NowPlayingInfo?
    private var scriptedSnapshots: [MediaPlayerTrackSnapshot] = []
    private var systemSnapshot: MediaPlayerTrackSnapshot?
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

    init(systemBridge: SystemNowPlayingBridge? = nil) {
        let systemBridge = systemBridge ?? SystemNowPlayingBridge()
        self.systemBridge = systemBridge
        systemBridge.onChange = { [weak self] snapshot in
            guard let self else { return }

            // Playback starting elsewhere overrides a manual pick.
            if let snapshot, snapshot.isPlaying, snapshot.source.player != preferredPlayer {
                preferredPlayer = nil
            }

            systemSnapshot = snapshot
            chooseAndPublish()
        }
    }

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

        systemBridge.start()
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
        systemBridge.stop()
        scriptedSnapshots = []
        systemSnapshot = nil
        current = nil
    }

    func refresh() {
        pendingRefresh?.cancel()
        pendingRefresh = nil

        guard isStarted else { return }

        let players = MediaPlayerApp.allCases.filter(\.isRunning)

        guard !players.isEmpty else {
            scriptedSnapshots = []
            chooseAndPublish()
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

    func send(_ command: MediaCommand, to source: NowPlayingSource) {
        guard let player = source.player, player.isRunning else {
            systemBridge.send(command)
            return
        }

        lastActivePlayer = player
        runScript(Self.commandScript(command, for: player))
    }

    func seek(to seconds: TimeInterval, in source: NowPlayingSource) {
        guard let player = source.player, player.isRunning else {
            systemBridge.seek(to: seconds)
            return
        }

        // Spotify and Music both take the position in seconds.
        let position = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), max(seconds, 0))
        runScript("tell application id \"\(player.bundleIdentifier)\" to set player position to \(position)")
    }

    func setVolume(_ volume: Double, for player: MediaPlayerApp) {
        guard player.isRunning else { return }

        let percent = Int((min(max(volume, 0), 1) * 100).rounded())
        runScript("tell application id \"\(player.bundleIdentifier)\" to set sound volume to \(percent)", refreshDelay: 0.6)
    }

    private func runScript(_ source: String, refreshDelay: TimeInterval = 0.3) {
        scriptQueue.async { [weak self] in
            _ = Self.run(source)

            Task { @MainActor in
                self?.scheduleRefresh(after: refreshDelay)
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

        scriptedSnapshots = snapshots
        chooseAndPublish()
    }

    private func chooseAndPublish() {
        guard isStarted else { return }

        guard let chosen = Self.choose(
            scripted: scriptedSnapshots,
            system: systemSnapshot,
            preferred: preferredPlayer,
            lastActive: lastActivePlayer,
            current: current?.source
        ) else {
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

    /// Picks the session to show. The system session is what Control Center
    /// shows, so it wins over a paused scripted player; a scripted snapshot of
    /// the same app replaces it, since it also carries the player volume.
    nonisolated static func choose(
        scripted: [MediaPlayerTrackSnapshot],
        system: MediaPlayerTrackSnapshot?,
        preferred: MediaPlayerApp?,
        lastActive: MediaPlayerApp?,
        current: NowPlayingSource?
    ) -> MediaPlayerTrackSnapshot? {
        if let preferred, let pick = scripted.first(where: { $0.source.player == preferred }) {
            return pick
        }

        if let system {
            let scriptedTwin = scripted.first { $0.source == system.source }

            if system.isPlaying || !scripted.contains(where: \.isPlaying) {
                return scriptedTwin ?? system
            }
        }

        // No system session (or it is paused while a scripted player plays):
        // prefer what is audible, then the player that last changed.
        return scripted.first(where: \.isPlaying)
            ?? scripted.first(where: { $0.source.player == lastActive })
            ?? scripted.first(where: { $0.source == current })
            ?? scripted.first
    }

    private func publish(_ info: NowPlayingInfo?) {
        current = info
        onChange?(info)
    }

    private func loadArtwork(for snapshot: MediaPlayerTrackSnapshot, key: String) {
        if let data = snapshot.artworkData {
            storeArtwork(data, key: key)
            return
        }

        guard !artworkLoadingKeys.contains(key), !artworkUnavailableKeys.contains(key) else { return }
        artworkLoadingKeys.insert(key)

        let queue = scriptQueue

        Task { [weak self] in
            let data = await Self.artworkData(for: snapshot, queue: queue)
            guard let self else { return }

            self.artworkLoadingKeys.remove(key)

            guard let data else {
                self.artworkUnavailableKeys.insert(key)
                return
            }

            self.storeArtwork(data, key: key)
        }
    }

    private func storeArtwork(_ data: Data, key: String) {
        guard let image = NSImage(data: data) else {
            artworkUnavailableKeys.insert(key)
            return
        }

        if artworkCache.count >= Self.artworkCacheLimit {
            artworkCache.removeAll()
            artworkUnavailableKeys.removeAll()
        }
        let tint = image.islandTintColor
        artworkCache[key] = (image, tint)

        guard isStarted, var current, current.cacheKey == key else { return }
        current.artwork = image
        current.artworkTint = tint
        publish(current)
    }

    // MARK: - Scripting (runs on `scriptQueue`)

    nonisolated private static func artworkData(
        for snapshot: MediaPlayerTrackSnapshot,
        queue: DispatchQueue
    ) async -> Data? {
        if let url = snapshot.artworkURL {
            return try? await URLSession.shared.data(from: url).0
        }

        guard snapshot.source.player == .music else { return nil }

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
        guard let list = run(trackScript(for: player)), list.numberOfItems >= 9 else {
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
            artworkURL: artworkURLString.isEmpty ? nil : URL(string: artworkURLString),
            volume: number(9) / 100
        )
    }

    nonisolated private static func run(_ source: String) -> NSAppleEventDescriptor? {
        guard let script = NSAppleScript(source: source) else { return nil }

        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        return errorInfo == nil ? result : nil
    }

    /// Returns `{isPlaying, id, title, artist, album, durationSeconds, positionSeconds, artworkURL, volume}`
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
                    set trackID to persistent ID of trackRef
                    set trackInfo to {name of trackRef, artist of trackRef, album of trackRef}
                    return {isPlaying, trackID} & trackInfo & {duration of trackRef, trackPosition, "", sound volume}
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
                    set trackInfo to {name of trackRef, artist of trackRef, album of trackRef}
                    set trackDuration to (duration of trackRef) / 1000
                    return {isPlaying, id of trackRef} & trackInfo & {trackDuration, player position, artURL, sound volume}
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
        case .play: "play"
        case .pause: "pause"
        case .nextTrack: "next track"
        case .previousTrack: "previous track"
        }

        return "tell application id \"\(player.bundleIdentifier)\" to \(verb)"
    }
}
