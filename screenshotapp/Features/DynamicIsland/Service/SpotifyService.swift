import AppKit
import CryptoKit
import Foundation
import Network
import Security

nonisolated struct SpotifyQueueItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let artworkURL: URL?
    let duration: TimeInterval
}

nonisolated enum SpotifyError: Error, Equatable, Sendable {
    case missingClientID
    case notConnected
    case authorizationFailed
    case requestFailed
    /// Spotify answered 204: no active device / nothing playing.
    case nothingPlaying
}

nonisolated private struct SpotifyTokens: Codable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
}

/// Spotify Web API access for the "Up Next" queue, using the Authorization
/// Code + PKCE flow (no client secret). The user registers their own Spotify
/// app and pastes its Client ID in Settings; the redirect URI is a one-shot
/// loopback listener (`http://127.0.0.1:43821/callback`), which Spotify allows
/// for desktop apps. Tokens live in DeskCast's own keychain item.
nonisolated final class SpotifyService: @unchecked Sendable {
    static let redirectURI = "http://127.0.0.1:43821/callback"
    private static let port: NWEndpoint.Port = 43821
    private static let scopes = "user-read-playback-state user-read-currently-playing"
    private static let keychainService = "com.ahmetbugraozcan.screenshotapp.spotify"

    private let lock = NSLock()
    private var tokens: SpotifyTokens?
    private var hasLoadedTokens = false
    private var listener: NWListener?

    /// The keychain is read lazily: a read can wait on a keychain access prompt
    /// (e.g. after the app's signature changed), which must never block launch
    /// or the main thread.
    init() {}

    /// Reads stored tokens once, off the main thread.
    func loadStoredTokensIfNeeded() async {
        lock.lock()
        let needsLoad = !hasLoadedTokens
        hasLoadedTokens = true
        lock.unlock()

        guard needsLoad else { return }

        let loaded = await Task.detached(priority: .utility) { Self.loadTokens() }.value

        lock.lock()
        if tokens == nil {
            tokens = loaded
        }
        lock.unlock()
    }

    var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return tokens != nil
    }

    // MARK: - Authorization

    /// Opens the Spotify consent page in the browser and waits for the redirect.
    func connect(clientID: String) async throws {
        let clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else { throw SpotifyError.missingClientID }

        let verifier = Self.randomURLSafeString(length: 64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
        let state = Self.randomURLSafeString(length: 16)

        var components = URLComponents(string: "https://accounts.spotify.com/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "state", value: state)
        ]

        guard let authorizeURL = components?.url else { throw SpotifyError.authorizationFailed }

        let code = try await waitForAuthorizationCode(expectedState: state) {
            _ = await MainActor.run {
                NSWorkspace.shared.open(authorizeURL)
            }
        }

        let tokens = try await requestTokens(parameters: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
            "client_id": clientID,
            "code_verifier": verifier
        ], previousRefreshToken: nil)

        store(tokens)
    }

    func disconnect() {
        lock.lock()
        tokens = nil
        hasLoadedTokens = true
        lock.unlock()
        Self.deleteTokens()
    }

    /// Serves one request on the loopback port and returns its `code`.
    private func waitForAuthorizationCode(
        expectedState: String,
        onReady: @escaping @Sendable () async -> Void
    ) async throws -> String {
        // Bound to loopback only, so nothing on the network can reach it.
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: Self.port)
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters)

        lock.lock()
        self.listener?.cancel()
        self.listener = listener
        lock.unlock()

        defer {
            listener.cancel()
        }

        return try await withCheckedThrowingContinuation { continuation in
            let resumed = ResumeOnce()

            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    Task { await onReady() }
                case .failed:
                    if resumed.claim() { continuation.resume(throwing: SpotifyError.authorizationFailed) }
                default:
                    break
                }
            }

            listener.newConnectionHandler = { connection in
                connection.start(queue: .global(qos: .userInitiated))
                connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, _ in
                    let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    let query = Self.callbackQuery(fromHTTPRequest: request)
                    let succeeded = query["state"] == expectedState && query["code"] != nil

                    let body = succeeded
                        ? "<h2>DeskCast is connected to Spotify.</h2><p>You can close this tab.</p>"
                        : "<h2>Spotify connection failed.</h2><p>Return to DeskCast and try again.</p>"
                    let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n"
                        + "<html><body style=\"font-family:-apple-system;text-align:center;margin-top:80px\">\(body)</body></html>"

                    connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                        connection.cancel()
                    })

                    // Ignore stray requests (e.g. favicon) that carry no code.
                    guard query["code"] != nil || query["error"] != nil else { return }

                    guard resumed.claim() else { return }

                    if succeeded, let code = query["code"] {
                        continuation.resume(returning: code)
                    } else {
                        continuation.resume(throwing: SpotifyError.authorizationFailed)
                    }
                }
            }

            listener.start(queue: .global(qos: .userInitiated))

            // Give up if the browser flow isn't finished in five minutes.
            DispatchQueue.global().asyncAfter(deadline: .now() + 300) {
                if resumed.claim() {
                    listener.cancel()
                    continuation.resume(throwing: SpotifyError.authorizationFailed)
                }
            }
        }
    }

    private static func callbackQuery(fromHTTPRequest request: String) -> [String: String] {
        // "GET /callback?code=...&state=... HTTP/1.1"
        guard let firstLine = request.split(separator: "\r\n").first else { return [:] }

        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2, let components = URLComponents(string: "http://127.0.0.1" + parts[1]) else {
            return [:]
        }

        return Dictionary(
            (components.queryItems ?? []).compactMap { item in item.value.map { (item.name, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    // MARK: - Tokens

    private func requestTokens(parameters: [String: String], previousRefreshToken: String?) async throws -> SpotifyTokens {
        guard let url = URL(string: "https://accounts.spotify.com/api/token") else { throw SpotifyError.authorizationFailed }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncoded(parameters).data(using: .utf8)

        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            (response as? HTTPURLResponse)?.statusCode == 200,
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let accessToken = json["access_token"] as? String
        else {
            throw SpotifyError.authorizationFailed
        }

        let expiresIn = (json["expires_in"] as? NSNumber)?.doubleValue ?? 3600

        // Refresh responses may omit a new refresh token; keep the old one.
        guard let refreshToken = json["refresh_token"] as? String ?? previousRefreshToken else {
            throw SpotifyError.authorizationFailed
        }

        return SpotifyTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(expiresIn - 60)
        )
    }

    private func validAccessToken(clientID: String, forceRefresh: Bool = false) async throws -> String {
        await loadStoredTokensIfNeeded()

        lock.lock()
        let current = tokens
        lock.unlock()

        guard let current else { throw SpotifyError.notConnected }

        if !forceRefresh, current.expiresAt > Date() {
            return current.accessToken
        }

        do {
            let refreshed = try await requestTokens(parameters: [
                "grant_type": "refresh_token",
                "refresh_token": current.refreshToken,
                "client_id": clientID
            ], previousRefreshToken: current.refreshToken)

            store(refreshed)
            return refreshed.accessToken
        } catch {
            // A revoked refresh token means the user has to connect again.
            disconnect()
            throw SpotifyError.notConnected
        }
    }

    private func store(_ tokens: SpotifyTokens) {
        lock.lock()
        self.tokens = tokens
        lock.unlock()
        Self.saveTokens(tokens)
    }

    // MARK: - Queue

    func queue(clientID: String, limit: Int = 10) async throws -> [SpotifyQueueItem] {
        guard let url = URL(string: "https://api.spotify.com/v1/me/player/queue") else { throw SpotifyError.requestFailed }

        var token = try await validAccessToken(clientID: clientID)

        for attempt in 0..<2 {
            var request = URLRequest(url: url, timeoutInterval: 12)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let status = (response as? HTTPURLResponse)?.statusCode
            else {
                throw SpotifyError.requestFailed
            }

            switch status {
            case 200:
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let items = json["queue"] as? [[String: Any]]
                else {
                    throw SpotifyError.requestFailed
                }

                return Array(items.compactMap(Self.queueItem(from:)).prefix(limit))
            case 204:
                throw SpotifyError.nothingPlaying
            case 401 where attempt == 0:
                token = try await validAccessToken(clientID: clientID, forceRefresh: true)
            default:
                throw SpotifyError.requestFailed
            }
        }

        throw SpotifyError.requestFailed
    }

    private static func queueItem(from json: [String: Any]) -> SpotifyQueueItem? {
        guard let name = json["name"] as? String else { return nil }

        let id = json["uri"] as? String ?? json["id"] as? String ?? UUID().uuidString
        let artists = (json["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
        let showName = (json["show"] as? [String: Any])?["name"] as? String
        let images = (json["album"] as? [String: Any])?["images"] as? [[String: Any]]
            ?? json["images"] as? [[String: Any]]
            ?? []
        // Images are largest first; the smallest is plenty for a thumbnail.
        let artworkURL = (images.last?["url"] as? String).flatMap(URL.init(string:))

        return SpotifyQueueItem(
            id: id,
            title: name,
            subtitle: artists.isEmpty ? (showName ?? "") : artists.joined(separator: ", "),
            artworkURL: artworkURL,
            duration: ((json["duration_ms"] as? NSNumber)?.doubleValue ?? 0) / 1000
        )
    }

    // MARK: - Helpers

    private static func formEncoded(_ parameters: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")

        return parameters
            .map { key, value in
                "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
            }
            .joined(separator: "&")
    }

    private static func randomURLSafeString(length: Int) -> String {
        let characters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in characters[Int.random(in: 0..<characters.count, using: &generator)] })
    }

    private static func loadTokens() -> SpotifyTokens? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?

        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else {
            return nil
        }

        return try? JSONDecoder().decode(SpotifyTokens.self, from: data)
    }

    private static func saveTokens(_ tokens: SpotifyTokens) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }

        deleteTokens()

        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "tokens",
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(item as CFDictionary, nil)
    }

    private static func deleteTokens() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Makes sure a continuation resumes exactly once across racing callbacks.
nonisolated private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var isClaimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard !isClaimed else { return false }
        isClaimed = true
        return true
    }
}

nonisolated private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
