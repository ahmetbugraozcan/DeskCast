import AppKit
import Combine

/// Spotify Web API connection state, shared by Settings and the island.
@MainActor
final class SpotifyAccountViewModel: ObservableObject {
    @Published var clientID: String {
        didSet {
            UserDefaults.standard.set(clientID, forKey: DynamicIslandSettings.Keys.spotifyClientID)
        }
    }

    @Published private(set) var isConnected: Bool
    @Published private(set) var isConnecting = false
    @Published private(set) var errorMessage: String?

    let service: SpotifyService

    init(service: SpotifyService = SpotifyService()) {
        self.service = service
        clientID = UserDefaults.standard.string(forKey: DynamicIslandSettings.Keys.spotifyClientID) ?? ""
        isConnected = service.isConnected
    }

    var hasClientID: Bool {
        !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func connect() {
        guard !isConnecting else { return }

        isConnecting = true
        errorMessage = nil
        let service = service
        let clientID = clientID

        Task {
            do {
                try await service.connect(clientID: clientID)
                errorMessage = nil
            } catch SpotifyError.missingClientID {
                errorMessage = AppLocalization.string("island.spotify.error.clientID")
            } catch {
                errorMessage = AppLocalization.string("island.spotify.error.connect")
            }

            isConnected = service.isConnected
            isConnecting = false
        }
    }

    func disconnect() {
        service.disconnect()
        isConnected = false
    }

    /// Re-reads the connection after an API call may have revoked it.
    func refreshConnectionState() {
        isConnected = service.isConnected
    }
}

/// Lyrics and the Spotify "Up Next" queue for the playing track.
@MainActor
final class NowPlayingExtrasViewModel: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case unavailable
    }

    enum QueueIssue: Equatable {
        case notSpotify
        case needsClientID
        case notConnected
        case nothingPlaying
        case failed
    }

    @Published private(set) var lyrics: Lyrics?
    @Published private(set) var lyricsState: LoadState = .idle
    @Published private(set) var queue: [SpotifyQueueItem] = []
    @Published private(set) var queueState: LoadState = .idle
    @Published private(set) var queueIssue: QueueIssue?

    let account: SpotifyAccountViewModel
    private let lyricsService: LyricsService
    private var lyricsKey: String?
    private var lyricsTask: Task<Void, Never>?
    private var queueKey: String?
    private var queueTask: Task<Void, Never>?
    private var queueLoadedAt: Date?

    init(account: SpotifyAccountViewModel, lyricsService: LyricsService = LyricsService()) {
        self.account = account
        self.lyricsService = lyricsService
    }

    func loadLyrics(for nowPlaying: NowPlayingInfo) {
        guard lyricsKey != nowPlaying.cacheKey else { return }

        lyricsKey = nowPlaying.cacheKey
        lyricsTask?.cancel()
        lyrics = nil
        lyricsState = .loading

        let service = lyricsService
        let key = nowPlaying.cacheKey
        let title = nowPlaying.title
        let artist = nowPlaying.artist
        let album = nowPlaying.album
        let duration = nowPlaying.duration

        lyricsTask = Task { [weak self] in
            let result = await service.lyrics(title: title, artist: artist, album: album, duration: duration)
            guard !Task.isCancelled, let self, self.lyricsKey == key else { return }
            self.lyrics = result
            self.lyricsState = result == nil ? .unavailable : .loaded
        }
    }

    /// Reloads when the track changes, or after 15 s for the same track.
    func loadQueue(for nowPlaying: NowPlayingInfo) {
        guard nowPlaying.player == .spotify else {
            queue = []
            queueIssue = .notSpotify
            queueState = .unavailable
            return
        }

        guard account.hasClientID else {
            queueIssue = .needsClientID
            queueState = .unavailable
            return
        }

        guard account.isConnected else {
            queueIssue = .notConnected
            queueState = .unavailable
            return
        }

        let isFresh = queueKey == nowPlaying.cacheKey
            && queueLoadedAt.map { Date().timeIntervalSince($0) < 15 } == true

        guard !isFresh, queueTask == nil else { return }

        queueKey = nowPlaying.cacheKey
        if queue.isEmpty {
            queueState = .loading
        }

        let service = account.service
        let clientID = account.clientID

        queueTask = Task { [weak self] in
            let result: Result<[SpotifyQueueItem], Error>

            do {
                result = .success(try await service.queue(clientID: clientID))
            } catch {
                result = .failure(error)
            }

            guard let self else { return }
            self.queueTask = nil
            self.queueLoadedAt = Date()

            switch result {
            case .success(let items):
                self.queue = items
                self.queueIssue = nil
                self.queueState = .loaded
            case .failure(let error):
                self.queue = []
                self.queueState = .unavailable

                switch error as? SpotifyError {
                case .nothingPlaying: self.queueIssue = .nothingPlaying
                case .notConnected:
                    self.queueIssue = .notConnected
                    self.account.refreshConnectionState()
                default: self.queueIssue = .failed
                }
            }
        }
    }
}
