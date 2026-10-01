import Foundation

nonisolated enum IntegrationError: LocalizedError, Equatable {
    case missingKey
    case missingURL
    case unauthorized
    case status(Int)
    case unreadable

    var errorDescription: String? {
        switch self {
        case .missingKey: AppLocalization.string("agentHub.integrations.error.key")
        case .missingURL: AppLocalization.string("agentHub.integrations.error.url")
        case .unauthorized: AppLocalization.string("agentHub.integrations.error.unauthorized")
        case .status(let code): AppLocalization.formatted("agentHub.integrations.error.status", code)
        case .unreadable: AppLocalization.string("agentHub.integrations.error.unreadable")
        }
    }
}

@MainActor
protocol IntegrationFetching {
    func fetch(_ integration: AgentIntegration, key: String, baseURL: String?) async throws -> IntegrationSnapshot
    /// Re-runs a failed n8n execution.
    func retryN8n(executionID: String, key: String, baseURL: String) async throws
}

/// Reads each service's public API with the user's key. Only services the
/// user turned on are ever called.
final class IntegrationClient: IntegrationFetching {
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        return URLSession(configuration: configuration)
    }()

    func fetch(_ integration: AgentIntegration, key: String, baseURL: String?) async throws -> IntegrationSnapshot {
        switch integration {
        case .stripe:
            let auth = "Basic " + Data("\(key):".utf8).base64EncodedString()
            async let balance = get("https://api.stripe.com/v1/balance", auth: auth)
            async let charges = get("https://api.stripe.com/v1/charges?limit=5", auth: auth)
            guard let total = IntegrationParsers.stripeBalance(try await balance) else { throw IntegrationError.unreadable }
            let payments = IntegrationParsers.stripePayments(try await charges)
            return .stripe(StripeSnapshot(balance: total.amount, currency: total.currency, payments: payments))
        case .vercel:
            let data = try await get("https://api.vercel.com/v6/deployments?limit=6", auth: "Bearer \(key)")
            return .vercel(IntegrationParsers.vercelDeployments(data))
        case .n8n:
            return .n8n(try await n8nExecutions(key: key, baseURL: baseURL))
        case .resend:
            let result = IntegrationParsers.resendEmails(try await get("https://api.resend.com/emails?limit=20", auth: "Bearer \(key)"))
            return .resend(emails: Array(result.emails.prefix(5)), total: result.total)
        case .github:
            let headers = ["Accept": "application/vnd.github+json"]
            async let user = get("https://api.github.com/user", auth: "Bearer \(key)", headers: headers)
            async let repos = get("https://api.github.com/user/repos?per_page=100&affiliation=owner&sort=pushed", auth: "Bearer \(key)", headers: headers)
            guard let summary = IntegrationParsers.gitHubSummary(user: try await user, repositories: try await repos) else {
                throw IntegrationError.unreadable
            }
            return .github(summary)
        case .notion:
            let body: [String: Any] = ["sort": ["direction": "descending", "timestamp": "last_edited_time"], "page_size": 4]
            let data = try await get(
                "https://api.notion.com/v1/search", auth: "Bearer \(key)",
                headers: ["Notion-Version": "2022-06-28", "Content-Type": "application/json"],
                method: "POST", body: try JSONSerialization.data(withJSONObject: body)
            )
            return .notion(IntegrationParsers.notionPages(data))
        case .calcom:
            let data = try await get(
                "https://api.cal.com/v2/bookings?status=upcoming&take=5", auth: "Bearer \(key)",
                headers: ["cal-api-version": "2024-08-13"]
            )
            return .calcom(Array(IntegrationParsers.calBookings(data).prefix(5)))
        }
    }

    private func n8nExecutions(key: String, baseURL: String?) async throws -> [N8nExecution] {
        guard let base = Self.normalized(baseURL) else { throw IntegrationError.missingURL }
        let headers = ["X-N8N-API-KEY": key]
        async let executions = get("\(base)/api/v1/executions?limit=6", headers: headers)
        async let workflows = get("\(base)/api/v1/workflows?limit=250", headers: headers)
        let names = (try? await IntegrationParsers.n8nWorkflowNames(workflows)) ?? [:]
        return IntegrationParsers.n8nExecutions(try await executions).map { execution in
            var execution = execution
            if execution.workflowName == nil, let id = execution.workflowID {
                execution.workflowName = names[id]
            }
            return execution
        }
    }

    func retryN8n(executionID: String, key: String, baseURL: String) async throws {
        guard let base = Self.normalized(baseURL) else { throw IntegrationError.missingURL }
        _ = try await get("\(base)/api/v1/executions/\(executionID)/retry", headers: ["X-N8N-API-KEY": key], method: "POST")
    }

    /// "https://n8n.example.com/" → "https://n8n.example.com"; only https.
    nonisolated static func normalized(_ url: String?) -> String? {
        guard var url = url?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty else { return nil }
        while url.hasSuffix("/") {
            url.removeLast()
        }
        guard let parsed = URL(string: url), parsed.scheme == "https", parsed.host != nil else { return nil }
        return url
    }

    private func get(
        _ address: String,
        auth: String? = nil,
        headers: [String: String] = [:],
        method: String = "GET",
        body: Data? = nil
    ) async throws -> Data {
        guard let url = URL(string: address) else { throw IntegrationError.unreadable }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        if let auth {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300: return data
        case 401, 403: throw IntegrationError.unauthorized
        default: throw IntegrationError.status(status)
        }
    }
}
