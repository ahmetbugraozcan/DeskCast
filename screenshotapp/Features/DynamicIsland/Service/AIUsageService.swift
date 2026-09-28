import Foundation
import Security

nonisolated struct AIUsageWindow: Equatable, Sendable {
    /// 0...1 share of the plan limit used in this window.
    let usedFraction: Double
    let resetsAt: Date?
}

nonisolated struct AIAgentUsage: Equatable, Sendable {
    var plan: String?
    var session: AIUsageWindow?
    var weekly: AIUsageWindow?
    var lastActivity: Date?
    /// Why limits are missing (e.g. not signed in), for the panel to explain.
    var unavailableReason: AIUsageUnavailableReason?
}

nonisolated enum AIUsageUnavailableReason: Equatable, Sendable {
    case notInstalled
    case signedOut
    case tokenExpired
    case requestFailed
}

nonisolated struct AIDailySpend: Equatable, Sendable, Identifiable {
    let day: Date
    var cost: Double
    var tokens: Int
    var cacheReadTokens: Int

    var id: Date { day }
}

nonisolated struct AIUsageReport: Equatable, Sendable {
    var claude = AIAgentUsage()
    var codex = AIAgentUsage()
    /// Last seven days of Claude Code usage, oldest first.
    var dailySpend: [AIDailySpend] = []
}

/// Reads Claude Code and Codex usage from their local state:
/// - Claude plan limits: the OAuth usage endpoint, authorized with the token
///   Claude Code keeps in the login keychain ("Claude Code-credentials").
///   macOS asks once before DeskCast may read that item. The token is never
///   refreshed here (that would sign Claude Code out); an expired token just
///   hides the limits until Claude Code runs again.
/// - Claude spend: token usage in `~/.claude/projects/**/*.jsonl`, priced at
///   API list rates (an estimate of "API value", not a bill).
/// - Codex limits: the latest `rate_limits` event in `~/.codex/sessions`.
/// Runs its file work on a background queue; call `load()` from any context.
nonisolated final class AIUsageService: @unchecked Sendable {
    private let fileManager = FileManager.default
    private let lock = NSLock()
    /// Per-transcript aggregates keyed by path, reused while mtime/size match.
    private var transcriptCache: [String: TranscriptSummary] = [:]

    private var homeURL: URL {
        fileManager.homeDirectoryForCurrentUser
    }

    func load() async -> AIUsageReport {
        var report = AIUsageReport()
        report.claude = await claudeUsage()
        report.codex = codexUsage()
        report.dailySpend = claudeDailySpend()
        return report
    }

    // MARK: - Claude limits

    private struct ClaudeCredentials {
        let accessToken: String
        let expiresAt: Date?
        let subscriptionType: String?
    }

    private func claudeUsage() async -> AIAgentUsage {
        var usage = AIAgentUsage()
        let projectsURL = homeURL.appendingPathComponent(".claude/projects")
        usage.lastActivity = newestModificationDate(in: projectsURL, extensions: ["jsonl"], maxDepth: 2)

        guard fileManager.fileExists(atPath: homeURL.appendingPathComponent(".claude").path) else {
            usage.unavailableReason = .notInstalled
            return usage
        }

        guard let credentials = claudeCredentials() else {
            usage.unavailableReason = .signedOut
            return usage
        }

        usage.plan = credentials.subscriptionType?.capitalized

        if let expiresAt = credentials.expiresAt, expiresAt < Date() {
            usage.unavailableReason = .tokenExpired
            return usage
        }

        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else { return usage }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            (response as? HTTPURLResponse)?.statusCode == 200,
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            usage.unavailableReason = .requestFailed
            return usage
        }

        usage.session = Self.claudeWindow(json["five_hour"])
        usage.weekly = Self.claudeWindow(json["seven_day"])
        return usage
    }

    private static func claudeWindow(_ value: Any?) -> AIUsageWindow? {
        guard let window = value as? [String: Any],
              let utilization = (window["utilization"] as? NSNumber)?.doubleValue
        else {
            return nil
        }

        return AIUsageWindow(
            usedFraction: min(max(utilization / 100, 0), 1),
            resetsAt: (window["resets_at"] as? String).flatMap(parseISODate)
        )
    }

    private func claudeCredentials() -> ClaudeCredentials? {
        let data = keychainPassword(service: "Claude Code-credentials")
            ?? (try? Data(contentsOf: homeURL.appendingPathComponent(".claude/.credentials.json")))

        guard
            let data,
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth = json["claudeAiOauth"] as? [String: Any],
            let token = oauth["accessToken"] as? String,
            !token.isEmpty
        else {
            return nil
        }

        let expiresAt = (oauth["expiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }

        return ClaudeCredentials(
            accessToken: token,
            expiresAt: expiresAt,
            subscriptionType: oauth["subscriptionType"] as? String
        )
    }

    private func keychainPassword(service: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?

        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    // MARK: - Claude spend

    private struct TranscriptSummary {
        let modificationDate: Date
        let size: Int
        /// Keyed by start of day.
        let days: [Date: AIDailySpend]
    }

    private func claudeDailySpend() -> [AIDailySpend] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let firstDay = calendar.date(byAdding: .day, value: -6, to: today) else { return [] }

        var totals: [Date: AIDailySpend] = [:]
        let projectsURL = homeURL.appendingPathComponent(".claude/projects")

        for url in files(in: projectsURL, extensions: ["jsonl"], maxDepth: 3, modifiedAfter: firstDay) {
            guard let summary = transcriptSummary(for: url) else { continue }

            for (day, spend) in summary.days where day >= firstDay {
                var total = totals[day] ?? AIDailySpend(day: day, cost: 0, tokens: 0, cacheReadTokens: 0)
                total.cost += spend.cost
                total.tokens += spend.tokens
                total.cacheReadTokens += spend.cacheReadTokens
                totals[day] = total
            }
        }

        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay) else { return nil }
            return totals[day] ?? AIDailySpend(day: day, cost: 0, tokens: 0, cacheReadTokens: 0)
        }
    }

    private func transcriptSummary(for url: URL) -> TranscriptSummary? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])

        guard let modificationDate = values?.contentModificationDate, let size = values?.fileSize else {
            return nil
        }

        lock.lock()
        let cached = transcriptCache[url.path]
        lock.unlock()

        if let cached, cached.modificationDate == modificationDate, cached.size == size {
            return cached
        }

        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }

        let calendar = Calendar.current
        var days: [Date: AIDailySpend] = [:]
        // Streaming writes one line per content block, all carrying the same
        // message usage; count each message once.
        var seenMessageIDs = Set<String>()
        let usageMarker = Data("\"usage\"".utf8)

        for line in data.split(separator: UInt8(ascii: "\n")) where line.range(of: usageMarker) != nil {
            guard
                let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                json["type"] as? String == "assistant",
                let message = json["message"] as? [String: Any],
                let usage = message["usage"] as? [String: Any],
                let timestamp = (json["timestamp"] as? String).flatMap(Self.parseISODate)
            else {
                continue
            }

            if let id = message["id"] as? String {
                guard seenMessageIDs.insert(id).inserted else { continue }
            }

            func tokens(_ key: String) -> Int { (usage[key] as? NSNumber)?.intValue ?? 0 }

            let input = tokens("input_tokens")
            let output = tokens("output_tokens")
            let cacheWrite = tokens("cache_creation_input_tokens")
            let cacheRead = tokens("cache_read_input_tokens")
            let price = ModelPrice.forModel(message["model"] as? String ?? "")

            let cost = (Double(input) * price.input
                + Double(output) * price.output
                + Double(cacheWrite) * price.cacheWrite
                + Double(cacheRead) * price.cacheRead) / 1_000_000

            let day = calendar.startOfDay(for: timestamp)
            var spend = days[day] ?? AIDailySpend(day: day, cost: 0, tokens: 0, cacheReadTokens: 0)
            spend.cost += cost
            spend.tokens += input + output + cacheWrite + cacheRead
            spend.cacheReadTokens += cacheRead
            days[day] = spend
        }

        let summary = TranscriptSummary(modificationDate: modificationDate, size: size, days: days)

        lock.lock()
        transcriptCache[url.path] = summary
        lock.unlock()

        return summary
    }

    /// API list prices in USD per million tokens. Cache writes are billed at
    /// 1.25× input (5-minute cache); cache reads use each model's read rate.
    private struct ModelPrice {
        let input: Double
        let output: Double
        let cacheWrite: Double
        let cacheRead: Double

        init(input: Double, output: Double, cacheRead: Double) {
            self.input = input
            self.output = output
            cacheWrite = input * 1.25
            self.cacheRead = cacheRead
        }

        static func forModel(_ model: String) -> ModelPrice {
            let model = model.lowercased()

            if model.contains("fable") || model.contains("mythos") {
                return ModelPrice(input: 10, output: 50, cacheRead: 0.25)
            }

            if model.contains("opus-5-5") {
                return ModelPrice(input: 4, output: 20, cacheRead: 0.20)
            }

            if model.contains("opus-5") || model.contains("opus-4-8") || model.contains("opus-4-7")
                || model.contains("opus-4-6") || model.contains("opus-4-5") {
                return ModelPrice(input: 5, output: 25, cacheRead: 0.50)
            }

            if model.contains("opus") {
                return ModelPrice(input: 15, output: 75, cacheRead: 1.50)
            }

            if model.contains("sonnet-5") {
                return ModelPrice(input: 2, output: 10, cacheRead: 0.20)
            }

            if model.contains("haiku") {
                return ModelPrice(input: 1, output: 5, cacheRead: 0.10)
            }

            return ModelPrice(input: 3, output: 15, cacheRead: 0.30)
        }
    }

    // MARK: - Codex

    private func codexUsage() -> AIAgentUsage {
        var usage = AIAgentUsage()
        let codexURL = homeURL.appendingPathComponent(".codex")

        guard fileManager.fileExists(atPath: codexURL.path) else {
            usage.unavailableReason = .notInstalled
            return usage
        }

        usage.plan = codexPlan(codexURL: codexURL)

        let sessionsURL = codexURL.appendingPathComponent("sessions")
        let recentFiles = files(
            in: sessionsURL,
            extensions: ["jsonl"],
            maxDepth: 4,
            modifiedAfter: Date().addingTimeInterval(-8 * 24 * 3600)
        )
        .compactMap { url -> (URL, Date)? in
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return date.map { (url, $0) }
        }
        .sorted { $0.1 > $1.1 }

        usage.lastActivity = recentFiles.first?.1

        // The newest session may not have reported limits yet; look back a few.
        for (url, _) in recentFiles.prefix(5) {
            if let limits = latestCodexRateLimits(in: url) {
                usage.session = limits.primary
                usage.weekly = limits.secondary
                usage.plan = limits.plan ?? usage.plan
                break
            }
        }

        if usage.session == nil && usage.weekly == nil && usage.plan == nil {
            usage.unavailableReason = .signedOut
        }

        return usage
    }

    private struct CodexRateLimits {
        let primary: AIUsageWindow?
        let secondary: AIUsageWindow?
        let plan: String?
    }

    private func latestCodexRateLimits(in url: URL) -> CodexRateLimits? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }

        let marker = Data("\"rate_limits\"".utf8)

        for line in data.split(separator: UInt8(ascii: "\n")).reversed() where line.range(of: marker) != nil {
            guard
                let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                let payload = json["payload"] as? [String: Any] ?? json["msg"] as? [String: Any],
                let limits = payload["rate_limits"] as? [String: Any]
            else {
                continue
            }

            let lineDate = (json["timestamp"] as? String).flatMap(Self.parseISODate) ?? Date()

            func window(_ key: String) -> AIUsageWindow? {
                guard let value = limits[key] as? [String: Any],
                      let used = (value["used_percent"] as? NSNumber)?.doubleValue
                else {
                    return nil
                }

                var resetsAt: Date?

                if let absolute = (value["resets_at"] as? NSNumber)?.doubleValue {
                    resetsAt = Date(timeIntervalSince1970: absolute)
                } else if let relative = (value["resets_in_seconds"] as? NSNumber)?.doubleValue {
                    resetsAt = lineDate.addingTimeInterval(relative)
                }

                return AIUsageWindow(usedFraction: min(max(used / 100, 0), 1), resetsAt: resetsAt)
            }

            let primary = window("primary")
            let secondary = window("secondary")

            guard primary != nil || secondary != nil else { continue }

            return CodexRateLimits(primary: primary, secondary: secondary, plan: (limits["plan_type"] as? String)?.capitalized)
        }

        return nil
    }

    /// Plan from the ChatGPT id token in `auth.json` (JWT claim), if signed in with ChatGPT.
    private func codexPlan(codexURL: URL) -> String? {
        guard
            let data = try? Data(contentsOf: codexURL.appendingPathComponent("auth.json")),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tokens = json["tokens"] as? [String: Any],
            let idToken = tokens["id_token"] as? String
        else {
            return nil
        }

        let segments = idToken.split(separator: ".")
        guard segments.count >= 2 else { return nil }

        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)

        guard
            let payloadData = Data(base64Encoded: base64),
            let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
            let auth = payload["https://api.openai.com/auth"] as? [String: Any],
            let plan = auth["chatgpt_plan_type"] as? String
        else {
            return nil
        }

        return plan.capitalized
    }

    // MARK: - Files

    private func files(in directory: URL, extensions: Set<String>, maxDepth: Int, modifiedAfter: Date) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var result: [URL] = []

        for case let url as URL in enumerator {
            if enumerator.level > maxDepth {
                enumerator.skipDescendants()
                continue
            }

            guard extensions.contains(url.pathExtension) else { continue }

            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let date, date >= modifiedAfter {
                result.append(url)
            }
        }

        return result
    }

    private func newestModificationDate(in directory: URL, extensions: Set<String>, maxDepth: Int) -> Date? {
        files(in: directory, extensions: extensions, maxDepth: maxDepth, modifiedAfter: .distantPast)
            .compactMap { (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate }
            .max()
    }

    // ISO8601DateFormatter is thread-safe; shared because transcripts have
    // thousands of timestamps.
    nonisolated(unsafe) private static let fractionalDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let plainDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func parseISODate(_ string: String) -> Date? {
        fractionalDateFormatter.date(from: string) ?? plainDateFormatter.date(from: string)
    }
}
