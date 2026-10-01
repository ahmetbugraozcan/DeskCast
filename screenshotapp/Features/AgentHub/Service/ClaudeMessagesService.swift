import Foundation

@MainActor
protocol ClaudeMessaging: AnyObject {
    /// One Messages API call; returns the response body.
    func send(_ body: [String: Any], key: String) async throws -> Data
    func models(key: String) async -> [(id: String, name: String)]
}

/// Talks to the Anthropic API directly over HTTPS with the user's own key
/// (there is no Swift SDK). Nothing else is sent anywhere.
final class ClaudeMessagesService: ClaudeMessaging {
    private static let base = "https://api.anthropic.com/v1"
    private static let version = "2023-06-01"

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        // Web searches and long answers can take a while.
        configuration.timeoutIntervalForRequest = 300
        return URLSession(configuration: configuration)
    }()

    func send(_ body: [String: Any], key: String) async throws -> Data {
        guard let url = URL(string: "\(Self.base)/messages") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.version, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        if body["fallbacks"] != nil {
            request.setValue(ClaudeChatProtocol.fallbackBeta, forHTTPHeaderField: "anthropic-beta")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw ClaudeChatError.api(ClaudeChatProtocol.errorMessage(data, status: status, model: body["model"] as? String ?? ""))
        }
        return data
    }

    func models(key: String) async -> [(id: String, name: String)] {
        guard let url = URL(string: "\(Self.base)/models?limit=100") else { return [] }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.version, forHTTPHeaderField: "anthropic-version")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else {
            return []
        }
        return ClaudeChatProtocol.parseModels(data)
    }
}
