import Foundation

/// One line of a code change shown in the island.
nonisolated struct AgentCodeLine: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case context
        case removed
        case added
    }

    let kind: Kind
    /// The line's number in the file, when known.
    let number: Int?
    let text: String
}

/// The edit an agent is about to make (Edit, MultiEdit, Write, or a Codex
/// patch), as a short diff around the change.
nonisolated struct AgentCodeChange: Equatable, Sendable {
    let filePath: String
    let lines: [AgentCodeLine]

    var fileName: String {
        URL(fileURLWithPath: filePath).lastPathComponent
    }

    var fileExtension: String {
        URL(fileURLWithPath: filePath).pathExtension.lowercased()
    }

    var addedCount: Int { lines.filter { $0.kind == .added }.count }
    var removedCount: Int { lines.filter { $0.kind == .removed }.count }

    static let contextLines = 2
    static let maxLines = 16
    static let maxLineLength = 160

    /// The change a tool call describes. `fileText` is the file as it is
    /// before the edit (to number the lines); `nil` when unknown.
    static func make(tool: String, input: [String: Any], fileText: String?) -> AgentCodeChange? {
        switch tool {
        case "Edit":
            guard let path = input["file_path"] as? String,
                  let old = input["old_string"] as? String,
                  let new = input["new_string"] as? String else { return nil }
            return edit(path: path, old: old, new: new, fileText: fileText)
        case "MultiEdit":
            guard let path = input["file_path"] as? String,
                  let first = (input["edits"] as? [[String: Any]])?.first,
                  let old = first["old_string"] as? String,
                  let new = first["new_string"] as? String else { return nil }
            return edit(path: path, old: old, new: new, fileText: fileText)
        case "Write":
            guard let path = input["file_path"] as? String, let content = input["content"] as? String else { return nil }
            let lines = splitLines(content).enumerated().map { AgentCodeLine(kind: .added, number: $0.offset + 1, text: $0.element) }
            return AgentCodeChange(filePath: path, lines: Array(lines.prefix(maxLines)).map(clipped))
        default:
            for value in input.values {
                if let text = value as? String, let change = patch(text) {
                    return change
                }
            }
            return nil
        }
    }

    /// `old` replaced by `new`, with a little context when `old` is found in
    /// `fileText`.
    static func edit(path: String, old: String, new: String, fileText: String?) -> AgentCodeChange? {
        let oldLines = splitLines(old)
        let newLines = splitLines(new)
        guard oldLines != newLines else { return nil }

        var before: [AgentCodeLine] = []
        var after: [AgentCodeLine] = []
        var start: Int?

        if let fileText, !old.isEmpty, let range = fileText.range(of: old) {
            let fileLines = splitLines(fileText)
            let prefix = fileText[fileText.startIndex..<range.lowerBound]
            let firstIndex = prefix.reduce(0) { $1 == "\n" ? $0 + 1 : $0 }
            start = firstIndex + 1

            let lastIndex = firstIndex + oldLines.count - 1
            for index in max(0, firstIndex - contextLines)..<firstIndex where index < fileLines.count {
                before.append(AgentCodeLine(kind: .context, number: index + 1, text: fileLines[index]))
            }
            // Lines after the change are numbered as they'll be once it's made.
            let shift = newLines.count - oldLines.count
            let afterEnd = min(fileLines.count - 1, lastIndex + contextLines)
            if lastIndex + 1 <= afterEnd {
                for index in (lastIndex + 1)...afterEnd {
                    after.append(AgentCodeLine(kind: .context, number: index + 1 + shift, text: fileLines[index]))
                }
            }
        }

        // Lines both sides share at the start and end stay context.
        var head = 0
        while head < oldLines.count, head < newLines.count, oldLines[head] == newLines[head] {
            head += 1
        }
        var tail = 0
        while tail < oldLines.count - head, tail < newLines.count - head,
              oldLines[oldLines.count - 1 - tail] == newLines[newLines.count - 1 - tail] {
            tail += 1
        }

        var middle: [AgentCodeLine] = []
        func number(_ offset: Int) -> Int? { start.map { $0 + offset } }

        // Only the shared lines next to the change are shown.
        if head > contextLines { before = [] }
        if tail > contextLines { after = [] }
        for index in max(0, head - contextLines)..<head {
            middle.append(AgentCodeLine(kind: .context, number: number(index), text: oldLines[index]))
        }
        for index in head..<(oldLines.count - tail) {
            middle.append(AgentCodeLine(kind: .removed, number: number(index), text: oldLines[index]))
        }
        for index in head..<(newLines.count - tail) {
            middle.append(AgentCodeLine(kind: .added, number: number(index), text: newLines[index]))
        }
        let shift = newLines.count - oldLines.count
        for index in (oldLines.count - tail)..<min(oldLines.count, oldLines.count - tail + contextLines) {
            middle.append(AgentCodeLine(kind: .context, number: number(index + shift), text: oldLines[index]))
        }

        return AgentCodeChange(filePath: path, lines: trim(before: before, middle: middle, after: after).map(clipped))
    }

    /// The first file of a Codex `apply_patch` ("*** Begin Patch").
    static func patch(_ text: String) -> AgentCodeChange? {
        guard text.contains("*** Begin Patch") else { return nil }

        var path: String?
        var lines: [AgentCodeLine] = []
        var isAddedFile = false

        for line in splitLines(text) {
            if line.hasPrefix("*** ") {
                if path != nil, !lines.isEmpty { break }
                for prefix in ["*** Update File: ", "*** Add File: ", "*** Delete File: "] where line.hasPrefix(prefix) {
                    path = String(line.dropFirst(prefix.count))
                    isAddedFile = prefix == "*** Add File: "
                }
                continue
            }
            guard path != nil, !line.hasPrefix("@@") else { continue }

            if line.hasPrefix("+") {
                lines.append(AgentCodeLine(kind: .added, number: isAddedFile ? lines.count + 1 : nil, text: String(line.dropFirst())))
            } else if line.hasPrefix("-") {
                lines.append(AgentCodeLine(kind: .removed, number: nil, text: String(line.dropFirst())))
            } else {
                lines.append(AgentCodeLine(kind: .context, number: nil, text: String(line.dropFirst(line.hasPrefix(" ") ? 1 : 0))))
            }
        }

        guard let path, lines.contains(where: { $0.kind != .context }) else { return nil }
        return AgentCodeChange(filePath: path, lines: trim(before: [], middle: lines, after: []).map(clipped))
    }

    /// Keeps the change itself in view when it's longer than the island:
    /// context first goes, then the end of the change.
    private static func trim(before: [AgentCodeLine], middle: [AgentCodeLine], after: [AgentCodeLine]) -> [AgentCodeLine] {
        if before.count + middle.count + after.count <= maxLines {
            return before + middle + after
        }
        if middle.count + 1 <= maxLines {
            let room = maxLines - middle.count
            return Array(before.suffix(min(1, room))) + middle + Array(after.prefix(max(0, room - 1)))
        }
        // Start just before the first real change.
        let first = middle.firstIndex { $0.kind != .context } ?? 0
        let start = max(0, min(first - 1, middle.count - maxLines))
        return Array(middle[start...].prefix(maxLines))
    }

    private static func clipped(_ line: AgentCodeLine) -> AgentCodeLine {
        let text = line.text.replacingOccurrences(of: "\t", with: "    ")
        guard text.count > maxLineLength else {
            return AgentCodeLine(kind: line.kind, number: line.number, text: text)
        }
        return AgentCodeLine(kind: line.kind, number: line.number, text: String(text.prefix(maxLineLength)) + "…")
    }

    static func splitLines(_ text: String) -> [String] {
        var lines = text.components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
        if lines.count > 1, lines.last?.isEmpty == true {
            lines.removeLast()
        }
        return lines
    }
}

/// A shell command an agent ran and the end of its output.
nonisolated struct AgentCommandRun: Equatable, Sendable {
    let command: String
    var output: [String] = []
    var failed = false

    static let maxOutputLines = 4
    static let maxLineLength = 140

    /// The last lines of a PostToolUse `tool_response`: Claude Code sends
    /// `{stdout, stderr}`, Codex may send plain text or `{output}`.
    static func outputLines(from response: Any?) -> [String] {
        var text = ""
        if let string = response as? String {
            text = string
        } else if let object = response as? [String: Any] {
            let parts = ["stdout", "output", "stderr", "error"].compactMap { object[$0] as? String }.filter { !$0.isEmpty }
            text = parts.joined(separator: "\n")
        }

        let lines = stripANSI(text)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.suffix(maxOutputLines).map { $0.count > maxLineLength ? String($0.prefix(maxLineLength)) + "…" : $0 }
    }

    /// Removes terminal color codes ("\u{1B}[32m").
    static func stripANSI(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]", with: "", options: .regularExpression)
    }
}
