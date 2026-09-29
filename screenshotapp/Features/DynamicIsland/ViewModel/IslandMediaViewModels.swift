import AppKit
import Combine

/// Time-synced lyrics for the playing track.
@MainActor
final class NowPlayingExtrasViewModel: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case unavailable
    }

    @Published private(set) var lyrics: Lyrics?
    @Published private(set) var lyricsState: LoadState = .idle

    private let lyricsService: LyricsService
    private var lyricsKey: String?
    private var lyricsTask: Task<Void, Never>?

    init(lyricsService: LyricsService = LyricsService()) {
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
}
