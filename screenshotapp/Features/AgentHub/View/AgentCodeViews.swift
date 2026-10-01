import SwiftUI

private enum AgentCodePalette {
    static let editor = Color(red: 0.055, green: 0.06, blue: 0.075)
    static let gutter = Color.white.opacity(0.28)
    static let text = Color(red: 0.86, green: 0.88, blue: 0.92)
    static let removed = Color(red: 1, green: 0.42, blue: 0.45)
    static let added = Color(red: 0.36, green: 0.86, blue: 0.52)
    static let prompt = Color.white.opacity(0.4)
}

/// A small editor showing the edit an agent makes: the file's tab, line
/// numbers, removed lines struck through in red and added lines in green.
/// While `isLive`, the added lines are typed out.
struct AgentCodeDiffView: View {
    let change: AgentCodeChange
    var isLive = false
    var maxLines: Int?

    @State private var appearedAt = Date()

    private var lines: [AgentCodeLine] {
        maxLines.map { Array(change.lines.prefix($0)) } ?? change.lines
    }

    private var gutterWidth: CGFloat {
        let largest = lines.compactMap(\.number).max() ?? 0
        return largest == 0 ? 0 : CGFloat(String(largest).count) * 7 + 6
    }

    var body: some View {
        VStack(spacing: 0) {
            tab
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isLive)) { context in
                let typed = typedCharacters(at: context.date)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(lines.indices, id: \.self) { index in
                        row(index: index, typed: typed)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
            }
            .padding(.vertical, 4)
        }
        .background(AgentCodePalette.editor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onChange(of: change) { _, _ in appearedAt = Date() }
    }

    private var tab: some View {
        HStack(spacing: 6) {
            Text(Self.badge(for: change.fileExtension))
                .font(.system(size: 8, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 3)
                .frame(minWidth: 16, minHeight: 13)
                .background(RoundedRectangle(cornerRadius: 3).fill(Self.badgeColor(for: change.fileExtension)))
            Text(change.fileName)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
            if isLive {
                Circle().fill(Color.orange).frame(width: 5, height: 5)
            }
            Spacer(minLength: 6)
            if change.addedCount > 0 {
                Text("+\(change.addedCount)")
                    .foregroundStyle(AgentCodePalette.added)
            }
            if change.removedCount > 0 {
                Text("−\(change.removedCount)")
                    .foregroundStyle(AgentCodePalette.removed)
            }
        }
        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(Color.white.opacity(0.04))
    }

    private func row(index: Int, typed: Int?) -> some View {
        let line = lines[index]
        let text = visibleText(at: index, typed: typed)
        let isTyping = typed != nil && index == typingIndex(typed)

        return HStack(spacing: 6) {
            if gutterWidth > 0 {
                Text(line.number.map(String.init) ?? "")
                    .foregroundStyle(lineColor(line).opacity(line.kind == .context ? 1 : 0.9))
                    .frame(width: gutterWidth, alignment: .trailing)
            }
            Text(marker(line))
                .foregroundStyle(lineColor(line))
                .frame(width: 8)
            HStack(spacing: 0) {
                Text(text)
                    .strikethrough(line.kind == .removed, color: AgentCodePalette.removed.opacity(0.7))
                    .foregroundStyle(line.kind == .removed ? AgentCodePalette.removed.opacity(0.75) : AgentCodePalette.text)
                if isTyping {
                    Rectangle().fill(Color.white.opacity(0.85)).frame(width: 1.5, height: 12)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(.horizontal, 8)
        .frame(height: 16)
        .background(alignment: .leading) {
            if line.kind != .context {
                ZStack(alignment: .leading) {
                    lineColor(line).opacity(0.13)
                    lineColor(line).frame(width: 2)
                }
            }
        }
    }

    private func marker(_ line: AgentCodeLine) -> String {
        switch line.kind {
        case .context: " "
        case .removed: "-"
        case .added: "+"
        }
    }

    private func lineColor(_ line: AgentCodeLine) -> Color {
        switch line.kind {
        case .context: AgentCodePalette.gutter
        case .removed: AgentCodePalette.removed
        case .added: AgentCodePalette.added
        }
    }

    // MARK: Typing

    private var addedIndices: [Int] {
        lines.indices.filter { lines[$0].kind == .added }
    }

    /// The added line being typed now.
    private func typingIndex(_ typed: Int?) -> Int? {
        guard var remaining = typed else { return nil }
        for index in addedIndices {
            let count = lines[index].text.count
            if remaining < count { return index }
            remaining -= count
        }
        return nil
    }

    /// Characters of added text typed so far, or `nil` when all of it shows.
    private func typedCharacters(at date: Date) -> Int? {
        guard isLive else { return nil }
        let total = addedIndices.reduce(0) { $0 + lines[$1].text.count }
        let speed = max(60, Double(total) / 1.2)
        let typed = Int(date.timeIntervalSince(appearedAt) * speed)
        return typed >= total ? nil : typed
    }

    /// Added lines appear one after another as they're "typed".
    private func visibleText(at lineIndex: Int, typed: Int?) -> String {
        let line = lines[lineIndex]
        guard line.kind == .added, var remaining = typed else { return line.text }
        for index in addedIndices {
            if index == lineIndex {
                return String(line.text.prefix(max(0, remaining)))
            }
            remaining -= lines[index].text.count
        }
        return line.text
    }

    // MARK: File badge

    static func badge(for fileExtension: String) -> String {
        switch fileExtension {
        case "swift": "SW"
        case "ts", "tsx": "TS"
        case "js", "jsx", "mjs", "cjs": "JS"
        case "py": "PY"
        case "rs": "RS"
        case "go": "GO"
        case "json": "{}"
        case "md": "MD"
        case "html": "<>"
        case "css", "scss": "#"
        case "": "·"
        default: String(fileExtension.prefix(2)).uppercased()
        }
    }

    static func badgeColor(for fileExtension: String) -> Color {
        switch fileExtension {
        case "swift": Color(red: 0.94, green: 0.42, blue: 0.22)
        case "ts", "tsx": Color(red: 0.19, green: 0.47, blue: 0.78)
        case "js", "jsx", "mjs", "cjs": Color(red: 0.85, green: 0.7, blue: 0.1)
        case "py": Color(red: 0.22, green: 0.46, blue: 0.67)
        case "rs": Color(red: 0.72, green: 0.35, blue: 0.2)
        case "go": Color(red: 0.0, green: 0.6, blue: 0.75)
        default: Color.white.opacity(0.25)
        }
    }
}

/// `$ command` and the end of its output, like a terminal.
struct AgentTerminalBox: View {
    let run: AgentCommandRun
    var isRunning = false
    var maxOutputLines = AgentCommandRun.maxOutputLines

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("$")
                    .foregroundStyle(AgentCodePalette.prompt)
                Text(run.command)
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if isRunning {
                    ProgressView().controlSize(.mini).tint(.white)
                }
            }
            ForEach(Array(run.output.suffix(maxOutputLines).enumerated()), id: \.offset) { _, line in
                Text(Self.colored(line, failed: run.failed))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AgentCodePalette.editor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 1))
        .textSelection(.enabled)
    }

    private static let good = ["pass", "passed", "ok", "success", "succeeded", "✓", "✔", "done"]
    private static let bad = ["fail", "failed", "failure", "error", "errors", "✗", "✘"]

    /// Output words that tell how it went get colored, like a test runner's.
    static func colored(_ line: String, failed: Bool) -> AttributedString {
        var text = AttributedString(line)
        text.foregroundColor = failed ? AgentCodePalette.removed.opacity(0.85) : Color.white.opacity(0.6)
        for word in line.split(whereSeparator: { $0 == " " || $0 == ":" || $0 == "," }) {
            let lower = word.lowercased()
            let color: Color? = good.contains(lower) ? AgentCodePalette.added : bad.contains(lower) ? AgentCodePalette.removed : nil
            guard let color, let range = text.range(of: String(word)) else { continue }
            text[range].foregroundColor = color
        }
        return text
    }
}

/// The turn's last steps as a checklist under Bip: done ones ticked, the
/// running one spinning, and "Done" waiting at the end.
struct AgentStepChecklist: View {
    let session: AgentHubSession

    private var steps: [AgentHubStep] {
        Array(session.turnSteps.suffix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(steps) { step in
                let isCurrent = step.id == steps.last?.id && session.phase.isBusy && !step.isFinished
                row(
                    title: step.shortTitle,
                    state: isCurrent ? .running : step.isFailure ? .failed : .done
                )
            }
            if !steps.isEmpty || session.phase == .finished {
                row(title: AppLocalization.string("agentHub.phase.finished"), state: session.phase == .finished ? .done : .pending)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: steps.map(\.id))
    }

    private enum RowState {
        case done, running, failed, pending
    }

    private func row(title: String, state: RowState) -> some View {
        HStack(spacing: 6) {
            Group {
                switch state {
                case .done:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(AgentCodePalette.added)
                case .running:
                    ProgressView().controlSize(.mini).tint(.white).frame(width: 12, height: 12)
                case .failed:
                    Image(systemName: "xmark.circle.fill").foregroundStyle(AgentCodePalette.removed)
                case .pending:
                    Image(systemName: "circle.dashed").foregroundStyle(IslandPalette.tertiaryText)
                }
            }
            .font(.system(size: 11))
            .frame(width: 13)

            Text(title)
                .font(.system(size: 11, weight: state == .running ? .bold : .medium))
                .foregroundStyle(state == .pending ? IslandPalette.tertiaryText : state == .running ? .white : .white.opacity(0.7))
                .lineLimit(1)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
