import Foundation

nonisolated struct AIUsageWindow: Equatable, Sendable {
    /// 0...1 share of the plan limit used in this window.
    let usedFraction: Double
    let resetsAt: Date?

    /// Once the reset time has passed, the recorded usage belongs to an old
    /// window; the current one starts empty.
    func current(at now: Date) -> AIUsageWindow {
        guard let resetsAt, resetsAt <= now else { return self }
        return AIUsageWindow(usedFraction: 0, resetsAt: nil)
    }
}

nonisolated struct AIAgentUsage: Equatable, Sendable {
    var plan: String?
    var session: AIUsageWindow?
    var weekly: AIUsageWindow?
    var lastActivity: Date?
    /// When the limits were last read by their source (the Claude app).
    var limitsUpdatedAt: Date?
    /// Why limits are missing (e.g. not signed in), for the panel to explain.
    var unavailableReason: AIUsageUnavailableReason?
}

nonisolated enum AIUsageUnavailableReason: Equatable, Sendable {
    case notInstalled
    case signedOut
    /// Claude plan limits come from the Claude desktop app, which isn't here.
    case claudeAppMissing
    /// The Claude app hasn't recorded limits recently (its menu bar icon is off).
    case claudeAppStale
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
/// - Claude plan limits: the percentages the Claude desktop app records in
///   `~/Library/Application Support/Claude/plan-usage-history.json` while its
///   menu bar icon is on. No sign-in, keychain item or network request is used.
/// - Claude spend: token usage in `~/.claude/projects/**/*.jsonl`, priced at
///   API list rates (an estimate of "API value", not a bill).
/// - Codex limits: the latest `rate_limits` event in `~/.codex/sessions`.
/// Runs its file work on a background queue; call `load()` from any context.
nonisolated final class AIUsageService: @unchecked Sendable {
    private let fileManager = FileManager.default
    private let lock = NSLock()
    /// Per-transcript totals keyed by path; extended as files grow and saved
    /// to `cacheURL` so a relaunch doesn't re-read every transcript.
    private var transcriptCache: [String: TranscriptSpendSummary]?
    private let cacheURL: URL

    init(cacheURL: URL? = nil) {
        self.cacheURL = cacheURL ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DeskCast", isDirectory: true)
            .appendingPathComponent("ClaudeSpendCache.json")
    }

    private var homeURL: URL {
        fileManager.homeDirectoryForCurrentUser
    }

    func load() async -> AIUsageReport {
        var report = await loadLimits()
        report.dailySpend = loadSpend()
        return report
    }

    /// Plan limits only: a few small files, so the panel can show them
    /// before the (slower) spend scan finishes.
    func loadLimits() async -> AIUsageReport {
        var report = AIUsageReport()
        report.claude = await claudeUsage()
        report.codex = codexUsage()
        return report
    }

    /// Last seven days of Claude Code spend, oldest first.
    func loadSpend() -> [AIDailySpend] {
        claudeDailySpend()
    }

    // MARK: - Claude limits

    /// Latest reading in the Claude app's plan usage history.
    struct ClaudePlanUsage: Equatable {
        let session: AIUsageWindow?
        let weekly: AIUsageWindow?
        let updatedAt: Date
    }

    private static let sessionLength: TimeInterval = 5 * 3600
    private static let weekLength: TimeInterval = 7 * 86_400

    /// Just the 5-hour limit used (0...1), for the closed island: one small
    /// file read, no transcript scan.
    func claudeSessionUsage(now: Date = Date()) -> Double? {
        let historyURL = homeURL.appendingPathComponent("Library/Application Support/Claude/plan-usage-history.json")
        guard let data = try? Data(contentsOf: historyURL) else { return nil }
        return Self.claudePlanUsage(from: data, now: now)?.session?.usedFraction
    }

    private func claudeUsage() async -> AIAgentUsage {
        var usage = AIAgentUsage()
        let projectsURL = homeURL.appendingPathComponent(".claude/projects")
        usage.lastActivity = newestModificationDate(in: projectsURL, extensions: ["jsonl"], maxDepth: 2)

        let historyURL = homeURL.appendingPathComponent("Library/Application Support/Claude/plan-usage-history.json")

        guard let data = try? Data(contentsOf: historyURL) else {
            let hasClaudeCode = fileManager.fileExists(atPath: homeURL.appendingPathComponent(".claude").path)
            usage.unavailableReason = hasClaudeCode ? .claudeAppMissing : .notInstalled
            return usage
        }

        guard let planUsage = Self.claudePlanUsage(from: data, now: Date()) else {
            usage.unavailableReason = .claudeAppStale
            return usage
        }

        usage.session = planUsage.session
        usage.weekly = planUsage.weekly
        usage.limitsUpdatedAt = planUsage.updatedAt

        if usage.session == nil && usage.weekly == nil {
            usage.unavailableReason = .claudeAppStale
        }

        return usage
    }

    /// Parses `{"samples":[{"t":<ms>,"u":{"fh":<5h %>,"sd":<7d %>}}]}` and
    /// returns the newest sample. A reading older than its window says nothing
    /// about the current window, so it is dropped. Reset times aren't recorded.
    static func claudePlanUsage(from data: Data, now: Date) -> ClaudePlanUsage? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let samples = json["samples"] as? [[String: Any]]
        else {
            return nil
        }

        let newest = samples
            .compactMap { sample -> (date: Date, usage: [String: Any])? in
                guard let time = (sample["t"] as? NSNumber)?.doubleValue,
                      let usage = sample["u"] as? [String: Any]
                else {
                    return nil
                }

                return (Date(timeIntervalSince1970: time / 1000), usage)
            }
            .max { $0.date < $1.date }

        guard let newest else { return nil }

        let age = now.timeIntervalSince(newest.date)

        func window(_ key: String, length: TimeInterval) -> AIUsageWindow? {
            guard age < length, let percent = (newest.usage[key] as? NSNumber)?.doubleValue else { return nil }
            return AIUsageWindow(usedFraction: min(max(percent / 100, 0), 1), resetsAt: nil)
        }

        return ClaudePlanUsage(
            session: window("fh", length: sessionLength),
            weekly: window("sd", length: weekLength),
            updatedAt: newest.date
        )
    }

    // MARK: - Claude spend

    private func claudeDailySpend() -> [AIDailySpend] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let firstDay = calendar.date(byAdding: .day, value: -6, to: today) else { return [] }

        let projectsURL = homeURL.appendingPathComponent(".claude/projects")
        let urls = files(in: projectsURL, extensions: ["jsonl"], maxDepth: 3, modifiedAfter: firstDay)

        lock.lock()
        defer { lock.unlock() }

        let previous = transcriptCache ?? loadCache()
        var cache: [String: TranscriptSpendSummary] = [:]
        var totals: [Date: AIDailySpend] = [:]

        for url in urls {
            let cached = previous[url.path]
            guard let summary = transcriptSummary(for: url, cached: cached, calendar: calendar) else { continue }
            cache[url.path] = summary

            for day in summary.days where day.day >= firstDay {
                var total = totals[day.day] ?? AIDailySpend(day: day.day, cost: 0, tokens: 0, cacheReadTokens: 0)
                total.cost += day.cost
                total.tokens += day.tokens
                total.cacheReadTokens += day.cacheReadTokens
                totals[day.day] = total
            }
        }

        transcriptCache = cache
        if cache != previous { saveCache(cache) }

        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay) else { return nil }
            return totals[day] ?? AIDailySpend(day: day, cost: 0, tokens: 0, cacheReadTokens: 0)
        }
    }

    /// Reads only what was appended since the cached summary; a file that
    /// shrank or was replaced is read again from the start.
    private func transcriptSummary(for url: URL, cached: TranscriptSpendSummary?, calendar: Calendar) -> TranscriptSpendSummary? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        guard let modificationDate = values?.contentModificationDate, let size = values?.fileSize else { return nil }

        if let cached, cached.modificationDate == modificationDate, cached.fileSize == size {
            return cached
        }

        var summary = cached.flatMap { $0.parsedOffset <= size ? $0 : nil } ?? .empty
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: UInt64(summary.parsedOffset))
            if let chunk = try handle.readToEnd() {
                summary.consume(chunk, calendar: calendar) { model in
                    let price = ModelPrice.forModel(model)
                    return TokenRates(input: price.input, output: price.output, cacheWrite: price.cacheWrite, cacheRead: price.cacheRead)
                }
            }
        } catch {
            return nil
        }
        summary.modificationDate = modificationDate
        summary.fileSize = size
        return summary
    }

    private func loadCache() -> [String: TranscriptSpendSummary] {
        guard let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode([String: TranscriptSpendSummary].self, from: data) else { return [:] }
        return cache
    }

    private func saveCache(_ cache: [String: TranscriptSpendSummary]) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? fileManager.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: cacheURL, options: .atomic)
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

            let lineDate = (json["timestamp"] as? String).flatMap(ClaudeTranscriptScanner.parseISODate) ?? Date()

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
}
