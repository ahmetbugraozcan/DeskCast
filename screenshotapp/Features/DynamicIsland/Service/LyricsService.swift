import Foundation

nonisolated struct LyricLine: Identifiable, Equatable, Sendable {
    let id: Int
    /// Start time in seconds; nil for unsynced (plain) lyrics.
    let time: TimeInterval?
    let text: String
}

nonisolated struct Lyrics: Equatable, Sendable {
    let lines: [LyricLine]
    let isSynced: Bool

    /// Index of the line being sung at `elapsed`, for synced lyrics.
    func currentLineIndex(at elapsed: TimeInterval) -> Int? {
        guard isSynced else { return nil }
        return lines.lastIndex { ($0.time ?? 0) <= elapsed + 0.25 }
    }
}

/// Fetches lyrics from LRCLIB (lrclib.net), a free, keyless lyrics database
/// with time-synced lines. Spotify and Music don't expose their lyrics to
/// other apps. Only the track title, artist, album and duration are sent.
nonisolated final class LyricsService: @unchecked Sendable {
    private let lock = NSLock()
    private var cache: [String: Lyrics?] = [:]

    private static let userAgent = "DeskCast (https://github.com/ahmetbugraozcan/DeskCast)"

    /// nil when LRCLIB has no lyrics for the track (cached, so not re-asked).
    func lyrics(title: String, artist: String, album: String, duration: TimeInterval) async -> Lyrics? {
        let key = "\(title)|\(artist)|\(Int(duration))".lowercased()

        lock.lock()
        let cached = cache[key]
        lock.unlock()

        if let cached {
            return cached
        }

        var result = await fetchExact(title: title, artist: artist, album: album, duration: duration)

        if result == nil {
            result = await search(title: title, artist: artist, duration: duration)
        }

        lock.lock()
        cache[key] = .some(result)
        lock.unlock()

        return result
    }

    private func fetchExact(title: String, artist: String, album: String, duration: TimeInterval) async -> Lyrics? {
        var components = URLComponents(string: "https://lrclib.net/api/get")
        components?.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "album_name", value: album),
            URLQueryItem(name: "duration", value: String(Int(duration.rounded())))
        ]

        guard let url = components?.url,
              let json = await requestJSON(url) as? [String: Any]
        else {
            return nil
        }

        return Self.lyrics(from: json)
    }

    private func search(title: String, artist: String, duration: TimeInterval) async -> Lyrics? {
        var components = URLComponents(string: "https://lrclib.net/api/search")
        components?.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist)
        ]

        guard let url = components?.url,
              let results = await requestJSON(url) as? [[String: Any]]
        else {
            return nil
        }

        // Closest duration first, preferring entries with synced lyrics.
        let ranked = results.sorted { lhs, rhs in
            let lhsSynced = lhs["syncedLyrics"] is String
            let rhsSynced = rhs["syncedLyrics"] is String

            if lhsSynced != rhsSynced { return lhsSynced }

            let lhsDelta = abs(((lhs["duration"] as? NSNumber)?.doubleValue ?? 0) - duration)
            let rhsDelta = abs(((rhs["duration"] as? NSNumber)?.doubleValue ?? 0) - duration)
            return lhsDelta < rhsDelta
        }

        return ranked.lazy.compactMap(Self.lyrics(from:)).first
    }

    private func requestJSON(_ url: URL) async -> Any? {
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200
        else {
            return nil
        }

        return try? JSONSerialization.jsonObject(with: data)
    }

    private static func lyrics(from json: [String: Any]) -> Lyrics? {
        if json["instrumental"] as? Bool == true {
            return nil
        }

        if let synced = json["syncedLyrics"] as? String, let lyrics = parseLRC(synced) {
            return lyrics
        }

        guard let plain = json["plainLyrics"] as? String else { return nil }

        let lines = plain
            .components(separatedBy: .newlines)
            .enumerated()
            .map { LyricLine(id: $0.offset, time: nil, text: $0.element.trimmingCharacters(in: .whitespaces)) }

        return lines.isEmpty ? nil : Lyrics(lines: lines, isSynced: false)
    }

    /// Parses "[mm:ss.xx] text" lines; a line may carry several timestamps.
    static func parseLRC(_ source: String) -> Lyrics? {
        var entries: [(TimeInterval, String)] = []

        for rawLine in source.components(separatedBy: .newlines) {
            var line = Substring(rawLine)
            var times: [TimeInterval] = []

            while line.hasPrefix("["), let close = line.firstIndex(of: "]") {
                let tag = line[line.index(after: line.startIndex)..<close]
                line = line[line.index(after: close)...]

                let parts = tag.split(separator: ":")
                guard parts.count == 2,
                      let minutes = Double(parts[0]),
                      let seconds = Double(parts[1].replacingOccurrences(of: ",", with: "."))
                else {
                    continue
                }

                times.append(minutes * 60 + seconds)
            }

            let text = line.trimmingCharacters(in: .whitespaces)
            entries.append(contentsOf: times.map { ($0, text) })
        }

        guard !entries.isEmpty else { return nil }

        let lines = entries
            .sorted { $0.0 < $1.0 }
            .enumerated()
            .map { LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1) }

        return Lyrics(lines: lines, isSynced: true)
    }
}
