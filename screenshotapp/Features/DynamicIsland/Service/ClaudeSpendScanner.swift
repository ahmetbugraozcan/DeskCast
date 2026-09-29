import Foundation

/// One assistant message's token usage in a Claude Code transcript line.
nonisolated struct ClaudeUsageLine: Equatable, Sendable {
    let messageID: String?
    let model: String
    let timestamp: Date
    let input: Int
    let output: Int
    let cacheWrite: Int
    let cacheRead: Int
}

/// Pulls usage out of Claude Code JSONL lines without decoding the whole line:
/// assistant lines carry large content, and a week of transcripts can be
/// hundreds of megabytes. Only the small `usage` object is parsed as JSON.
nonisolated enum ClaudeTranscriptScanner {
    private static let usageKey = Data(#""usage":{"#.utf8)
    private static let assistantRole = Data(#""role":"assistant""#.utf8)
    private static let timestampKey = Data(#""timestamp":""#.utf8)
    private static let modelKey = Data(#""model":""#.utf8)
    private static let messageIDKey = Data(#""id":"msg_"#.utf8)
    /// `message.role` sits right after its model and id.
    private static let roleSearchLength = 800

    static func usage(in line: Data) -> ClaudeUsageLine? {
        guard let usageStart = line.range(of: usageKey, options: .backwards) else { return nil }
        let head = line.startIndex..<min(line.endIndex, line.startIndex + roleSearchLength)
        guard line.range(of: assistantRole, in: head) != nil,
              let timestampString = string(after: timestampKey, in: line, backwards: true),
              let timestamp = parseISODate(timestampString),
              let usageObject = object(startingAt: usageStart.upperBound - 1, in: line),
              let usage = try? JSONSerialization.jsonObject(with: usageObject) as? [String: Any] else {
            return nil
        }

        func tokens(_ key: String) -> Int { (usage[key] as? NSNumber)?.intValue ?? 0 }

        return ClaudeUsageLine(
            messageID: string(after: messageIDKey, in: line, backwards: false).map { "msg_" + $0 },
            model: string(after: modelKey, in: line, backwards: false) ?? "",
            timestamp: timestamp,
            input: tokens("input_tokens"),
            output: tokens("output_tokens"),
            cacheWrite: tokens("cache_creation_input_tokens"),
            cacheRead: tokens("cache_read_input_tokens")
        )
    }

    /// The `{…}` object starting at `start`, by brace matching (skipping strings).
    private static func object(startingAt start: Data.Index, in line: Data) -> Data? {
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < line.endIndex {
            let byte = line[index]
            if inString {
                if escaped {
                    escaped = false
                } else if byte == UInt8(ascii: "\\") {
                    escaped = true
                } else if byte == UInt8(ascii: "\"") {
                    inString = false
                }
            } else if byte == UInt8(ascii: "\"") {
                inString = true
            } else if byte == UInt8(ascii: "{") {
                depth += 1
            } else if byte == UInt8(ascii: "}") {
                depth -= 1
                if depth == 0 { return line[start...index] }
            }
            index += 1
        }
        return nil
    }

    /// The string value right after `key` (which ends with the opening quote).
    private static func string(after key: Data, in line: Data, backwards: Bool) -> String? {
        guard let keyRange = line.range(of: key, options: backwards ? .backwards : []),
              let end = line[keyRange.upperBound...].firstIndex(of: UInt8(ascii: "\"")) else { return nil }
        return String(data: line[keyRange.upperBound..<end], encoding: .utf8)
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

    static func parseISODate(_ string: String) -> Date? {
        fractionalDateFormatter.date(from: string) ?? plainDateFormatter.date(from: string)
    }
}

/// USD per million tokens for one model.
nonisolated struct TokenRates: Sendable {
    let input: Double
    let output: Double
    let cacheWrite: Double
    let cacheRead: Double
}

/// Per-transcript spend totals, extended as the file grows: only bytes after
/// `parsedOffset` are read again. Codable so a relaunch doesn't re-read
/// hundreds of megabytes.
nonisolated struct TranscriptSpendSummary: Codable, Equatable, Sendable {
    struct Day: Codable, Equatable, Sendable {
        var day: Date
        var cost: Double
        var tokens: Int
        var cacheReadTokens: Int
    }

    var modificationDate: Date
    var fileSize: Int
    /// Bytes consumed, up to the last complete line.
    var parsedOffset: Int
    var days: [Day]
    /// Streaming writes one line per content block with the same usage; the
    /// newest ids let an appended chunk skip a message counted before it.
    var recentMessageIDs: [String]

    static let empty = TranscriptSpendSummary(modificationDate: .distantPast, fileSize: 0, parsedOffset: 0, days: [], recentMessageIDs: [])

    private static let rememberedIDs = 64

    /// Adds the complete lines in `chunk` (which starts at `parsedOffset`).
    mutating func consume(_ chunk: Data, calendar: Calendar, rates ratesForModel: (String) -> TokenRates) {
        guard let lastNewline = chunk.lastIndex(of: UInt8(ascii: "\n")) else { return }
        let complete = chunk[chunk.startIndex...lastNewline]
        parsedOffset += complete.count

        var seen = Set(recentMessageIDs)
        var dayIndex = Dictionary(uniqueKeysWithValues: days.enumerated().map { ($1.day, $0) })
        let usageKey = Data(#""usage""#.utf8)

        for line in complete.split(separator: UInt8(ascii: "\n")) where line.range(of: usageKey) != nil {
            guard let usage = ClaudeTranscriptScanner.usage(in: line) else { continue }
            if let id = usage.messageID {
                guard seen.insert(id).inserted else { continue }
                recentMessageIDs.append(id)
            }

            let rates = ratesForModel(usage.model)
            let cost = (Double(usage.input) * rates.input
                + Double(usage.output) * rates.output
                + Double(usage.cacheWrite) * rates.cacheWrite
                + Double(usage.cacheRead) * rates.cacheRead) / 1_000_000
            let day = calendar.startOfDay(for: usage.timestamp)
            let index = dayIndex[day] ?? {
                days.append(Day(day: day, cost: 0, tokens: 0, cacheReadTokens: 0))
                dayIndex[day] = days.count - 1
                return days.count - 1
            }()
            days[index].cost += cost
            days[index].tokens += usage.input + usage.output + usage.cacheWrite + usage.cacheRead
            days[index].cacheReadTokens += usage.cacheRead
        }

        if recentMessageIDs.count > Self.rememberedIDs {
            recentMessageIDs.removeFirst(recentMessageIDs.count - Self.rememberedIDs)
        }
    }
}
