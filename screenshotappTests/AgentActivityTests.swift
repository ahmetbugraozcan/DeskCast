import Foundation
import Testing
@testable import screenshotapp

struct AgentTranscriptStateTests {
    private func line(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    private func claude(_ type: String, _ time: String, content: Any, stopReason: String? = nil, extra: [String: Any] = [:]) -> Data {
        var message: [String: Any] = ["role": type, "content": content]
        if let stopReason { message["stop_reason"] = stopReason }
        var object: [String: Any] = [
            "type": type,
            "timestamp": "2026-09-29T10:\(time).000Z",
            "cwd": "/Users/me/Projects/deskcast",
            "isSidechain": false,
            "message": message
        ]
        object.merge(extra) { _, new in new }
        return line(object)
    }

    @Test func claudeTurnRunsFromPromptToEndTurn() {
        var state = AgentTranscriptState(kind: .claude)

        #expect(state.consume(claude("user", "00:00", content: "Fix the bug")) == .started)
        #expect(state.isWorking)
        #expect(state.project == "deskcast")
        #expect(state.consume(claude("assistant", "00:05", content: [["type": "tool_use"]], stopReason: "tool_use")) == nil)
        #expect(state.consume(claude("user", "00:07", content: [["type": "tool_result", "content": "ok"]])) == nil)
        #expect(state.isWorking)
        #expect(state.consume(claude("assistant", "02:00", content: [["type": "text", "text": "Done"]], stopReason: "end_turn"))
            == .finished(duration: 120))
        #expect(!state.isWorking)
        // A second end_turn block of the same reply changes nothing.
        #expect(state.consume(claude("assistant", "02:01", content: [["type": "text", "text": "…"]], stopReason: "end_turn")) == nil)
    }

    @Test func claudeInterruptionsSidechainsAndCommandsDontLeaveATurnOpen() {
        var state = AgentTranscriptState(kind: .claude)

        #expect(state.consume(claude("user", "00:00", content: "<command-name>/model</command-name>")) == nil)
        #expect(state.consume(claude("user", "00:01", content: "Go", extra: ["isSidechain": true])) == nil)
        #expect(!state.isWorking)

        _ = state.consume(claude("user", "00:02", content: "Go"))
        #expect(state.consume(claude("user", "00:30", content: [["type": "text", "text": "[Request interrupted by user]"]]))
            == .interrupted)
        #expect(!state.isWorking)
    }

    @Test func claudeTurnSeenMidwayStartsAtTheFirstEntry() {
        var state = AgentTranscriptState(kind: .claude)
        #expect(state.consume(claude("user", "05:00", content: [["type": "tool_result"]])) == .started)
        #expect(state.turnStartedAt != nil)
    }

    @Test func codexTaskEventsDriveTheTurn() {
        var state = AgentTranscriptState(kind: .codex)

        _ = state.consume(line(["timestamp": "2026-09-29T10:00:00.000Z", "type": "session_meta", "payload": ["cwd": "/Users/me/app"]]))
        #expect(state.project == "app")
        #expect(state.consume(line(["timestamp": "2026-09-29T10:00:01.000Z", "type": "event_msg", "payload": ["type": "task_started"]]))
            == .started)
        #expect(state.consume(line(["timestamp": "2026-09-29T10:03:01.000Z", "type": "event_msg", "payload": ["type": "task_complete"]]))
            == .finished(duration: 180))

        _ = state.consume(line(["timestamp": "2026-09-29T10:04:00.000Z", "type": "event_msg", "payload": ["type": "task_started"]]))
        #expect(state.consume(line(["timestamp": "2026-09-29T10:04:10.000Z", "type": "event_msg", "payload": ["type": "turn_aborted"]]))
            == .interrupted)
    }

    @Test func codexSkipsUnrelatedLinesAndChatGPTProjectFolders() {
        var state = AgentTranscriptState(kind: .codex)
        _ = state.consume(line(["type": "session_meta", "payload": ["cwd": "/Users/me/.codex/.chatgpt-projects/g-p-123"]]))
        #expect(state.project == nil)
        #expect(state.consume(line(["type": "response_item", "payload": ["type": "reasoning"]])) == nil)
        #expect(!state.hasSeenTurnBoundary)
        _ = state.consume(line(["type": "event_msg", "payload": ["type": "task_complete"]]))
        #expect(state.hasSeenTurnBoundary)
    }

    @Test func codexSubthreadsAreMarked() {
        var state = AgentTranscriptState(kind: .codex)
        _ = state.consume(line(["type": "session_meta", "payload": ["parent_thread_id": "abc", "cwd": "/x"]]))
        #expect(state.isSubthread)
    }

    @Test func brokenAndHugeLinesAreIgnored() {
        var state = AgentTranscriptState(kind: .claude)
        #expect(state.consume(Data("{not json".utf8)) == nil)
        #expect(state.consume(Data(repeating: 0x20, count: AgentTranscriptState.maxParsedLineLength + 1)) == nil)
    }
}

@MainActor
struct AgentActivityServiceTests {
    /// Codex keeps its transcript open while it writes, which FSEvents doesn't
    /// report until the file is closed.
    @Test func codexWritesToAnOpenTranscriptAreSeen() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let folder = home.appendingPathComponent(".codex/sessions/2026/09/29", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let file = folder.appendingPathComponent("rollout-test.jsonl")
        try Data(#"{"type":"session_meta","payload":{"cwd":"/Users/me/app"}}"#.utf8 + [0x0A]).write(to: file)
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }

        let service = AgentActivityService(home: home)
        var sessions: [AgentSession] = []
        service.onUpdate = { sessions = $0 }
        service.start()
        defer { service.stop() }

        try await Task.sleep(for: .milliseconds(300))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(#"{"type":"event_msg","payload":{"type":"task_started"}}"#.utf8 + [0x0A]))

        for _ in 0..<50 where sessions.isEmpty {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(sessions.map(\.kind) == [.codex])
        #expect(sessions.first?.project == "app")
    }
}

@MainActor
final class FakeAgentActivity: AgentActivityProviding {
    var onUpdate: (@MainActor @Sendable ([AgentSession]) -> Void)?
    var onFinish: (@MainActor @Sendable (AgentSession, TimeInterval) -> Void)?
    private(set) var isStarted = false

    nonisolated func start() {
        MainActor.assumeIsolated { isStarted = true }
    }

    nonisolated func stop() {
        MainActor.assumeIsolated { isStarted = false }
    }

    func emit(_ sessions: [AgentSession]) { onUpdate?(sessions) }
    func finish(_ session: AgentSession, duration: TimeInterval) { onFinish?(session, duration) }
}
