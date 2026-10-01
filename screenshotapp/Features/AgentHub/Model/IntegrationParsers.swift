import Foundation

/// Reads each service's JSON into snapshots. Pure, unit-tested.
nonisolated enum IntegrationParsers {
    private static func json(_ data: Data) -> Any? {
        try? JSONSerialization.jsonObject(with: data)
    }

    static func date(_ string: String?) -> Date? {
        guard let string else { return nil }
        return (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(string))
            ?? (try? Date.ISO8601FormatStyle().parse(string))
    }

    private static func identifier(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? Int { return String(number) }
        return nil
    }

    // MARK: Stripe

    /// `GET /v1/balance`: available + pending in the first currency.
    static func stripeBalance(_ data: Data) -> (amount: Int, currency: String)? {
        guard let object = json(data) as? [String: Any] else { return nil }
        let buckets = (object["available"] as? [[String: Any]] ?? []) + (object["pending"] as? [[String: Any]] ?? [])
        guard let currency = buckets.first?["currency"] as? String else { return nil }
        let amount = buckets.filter { $0["currency"] as? String == currency }.compactMap { $0["amount"] as? Int }.reduce(0, +)
        return (amount, currency)
    }

    /// `GET /v1/charges`
    static func stripePayments(_ data: Data) -> [StripePayment] {
        guard let items = (json(data) as? [String: Any])?["data"] as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let id = item["id"] as? String, let amount = item["amount"] as? Int,
                  let currency = item["currency"] as? String else { return nil }
            let summary = item["description"] as? String
                ?? (item["billing_details"] as? [String: Any])?["name"] as? String
            let created = item["created"] as? TimeInterval ?? 0
            return StripePayment(
                id: id, amount: amount, currency: currency, summary: summary,
                date: Date(timeIntervalSince1970: created), succeeded: item["status"] as? String == "succeeded"
            )
        }
    }

    // MARK: Vercel

    /// `GET /v6/deployments`
    static func vercelDeployments(_ data: Data) -> [VercelDeployment] {
        guard let items = (json(data) as? [String: Any])?["deployments"] as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let id = item["uid"] as? String, let name = item["name"] as? String else { return nil }
            let meta = item["meta"] as? [String: Any] ?? [:]
            let created = (item["createdAt"] as? Double ?? item["created"] as? Double ?? 0) / 1000
            return VercelDeployment(
                id: id,
                project: name,
                url: item["url"] as? String ?? "",
                state: item["state"] as? String ?? item["readyState"] as? String ?? "",
                date: Date(timeIntervalSince1970: created),
                commit: meta["githubCommitMessage"] as? String ?? meta["gitlabCommitMessage"] as? String
                    ?? meta["bitbucketCommitMessage"] as? String,
                branch: meta["githubCommitRef"] as? String ?? meta["gitlabCommitRef"] as? String ?? meta["bitbucketCommitRef"] as? String
            )
        }
    }

    // MARK: n8n

    /// `GET /api/v1/executions` (an object with `data`, or a bare array).
    static func n8nExecutions(_ data: Data) -> [N8nExecution] {
        let object = json(data)
        let items = (object as? [String: Any])?["data"] as? [[String: Any]] ?? object as? [[String: Any]] ?? []
        return items.compactMap { item in
            guard let id = identifier(item["id"]) else { return nil }
            return N8nExecution(
                id: id,
                workflowID: identifier(item["workflowId"]),
                workflowName: (item["workflowData"] as? [String: Any])?["name"] as? String,
                status: item["status"] as? String ?? (item["finished"] as? Bool == true ? "success" : "running"),
                date: date(item["stoppedAt"] as? String) ?? date(item["startedAt"] as? String)
            )
        }
    }

    /// `GET /api/v1/workflows`: id → name.
    static func n8nWorkflowNames(_ data: Data) -> [String: String] {
        let object = json(data)
        let items = (object as? [String: Any])?["data"] as? [[String: Any]] ?? object as? [[String: Any]] ?? []
        var names: [String: String] = [:]
        for item in items {
            if let id = identifier(item["id"]), let name = item["name"] as? String {
                names[id] = name
            }
        }
        return names
    }

    // MARK: Resend

    /// `GET /emails`
    static func resendEmails(_ data: Data) -> (emails: [ResendEmail], total: Int?) {
        guard let object = json(data) as? [String: Any], let items = object["data"] as? [[String: Any]] else { return ([], nil) }
        let emails: [ResendEmail] = items.compactMap { item in
            guard let id = item["id"] as? String else { return nil }
            let recipients = item["to"] as? [String] ?? (item["to"] as? String).map { [$0] } ?? []
            return ResendEmail(
                id: id,
                recipients: recipients,
                subject: item["subject"] as? String ?? "",
                // Resend writes "2026-10-01 10:00:00.123+00"; ISO 8601 wants a "T".
                date: date((item["created_at"] as? String)?.replacingOccurrences(of: " ", with: "T")) ?? .distantPast,
                lastEvent: item["last_event"] as? String ?? ""
            )
        }
        return (emails, object["total"] as? Int ?? object["count"] as? Int)
    }

    // MARK: GitHub

    /// `GET /user` and `GET /user/repos`.
    static func gitHubSummary(user: Data, repositories: Data) -> GitHubSummary? {
        guard let user = json(user) as? [String: Any], let login = user["login"] as? String else { return nil }
        let repos = json(repositories) as? [[String: Any]] ?? []
        let owned = (user["public_repos"] as? Int ?? 0) + (user["owned_private_repos"] as? Int ?? user["total_private_repos"] as? Int ?? 0)
        return GitHubSummary(
            login: login,
            repositories: owned,
            stars: repos.compactMap { $0["stargazers_count"] as? Int }.reduce(0, +),
            followers: user["followers"] as? Int ?? 0
        )
    }

    // MARK: Notion

    /// `POST /v1/search`
    static func notionPages(_ data: Data) -> [NotionPage] {
        guard let items = (json(data) as? [String: Any])?["results"] as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let id = item["id"] as? String, let edited = date(item["last_edited_time"] as? String) else { return nil }
            let icon = item["icon"] as? [String: Any]
            return NotionPage(
                id: id,
                title: notionTitle(item) ?? "Untitled",
                emoji: icon?["type"] as? String == "emoji" ? icon?["emoji"] as? String : nil,
                date: edited,
                url: item["url"] as? String ?? "https://www.notion.so"
            )
        }
    }

    private static func notionTitle(_ item: [String: Any]) -> String? {
        func plain(_ value: Any?) -> String? {
            let text = (value as? [[String: Any]])?.compactMap { $0["plain_text"] as? String }.joined()
            return text?.isEmpty == false ? text : nil
        }
        if let title = plain(item["title"]) {
            return title
        }
        for property in (item["properties"] as? [String: Any] ?? [:]).values {
            guard let property = property as? [String: Any], property["type"] as? String == "title" else { continue }
            return plain(property["title"])
        }
        return nil
    }

    // MARK: Cal.com

    /// `GET /v2/bookings`
    static func calBookings(_ data: Data) -> [CalBooking] {
        guard let items = (json(data) as? [String: Any])?["data"] as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let id = identifier(item["id"]) ?? identifier(item["uid"]),
                  let start = date(item["start"] as? String ?? item["startTime"] as? String) else { return nil }
            let attendee = (item["attendees"] as? [[String: Any]])?.first
            return CalBooking(
                id: id,
                title: item["title"] as? String ?? "Meeting",
                start: start,
                attendee: attendee?["name"] as? String ?? attendee?["email"] as? String
            )
        }
        .sorted { $0.start < $1.start }
    }
}
