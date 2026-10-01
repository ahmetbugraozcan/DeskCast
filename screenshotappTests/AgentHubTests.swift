import Foundation
import Testing
@testable import screenshotapp

struct AgentHookEventTests {
    @Test func decodesToolCallsWithTheirMostTellingInput() throws {
        let event = try #require(AgentHookEvent(payload: [
            "hook_event_name": "PreToolUse",
            "session_id": "s1",
            "cwd": "/Users/me/Projects/deskcast",
            "tool_name": "Edit",
            "tool_input": ["file_path": "/Users/me/Projects/deskcast/App.swift", "old_string": "a"],
            "term_program": "Apple_Terminal",
            "tty": "/dev/ttys004"
        ]))

        #expect(event.kind == .preToolUse)
        #expect(event.toolSummary == "App.swift")
        #expect(event.terminal.tty == "/dev/ttys004")
        #expect(event.agent == nil)
    }

    @Test func readsQuestionsAndOtherAgentNames() throws {
        let event = try #require(AgentHookEvent(payload: [
            "hook_event_name": "PreToolUse",
            "session_id": "s1",
            "tool_name": "AskUserQuestion",
            "tool_input": ["questions": [["question": "Which one?", "options": [["label": "A"], ["label": "B"]]]]],
            "deskcast_agent": "my-tool"
        ]))

        #expect(event.question == AgentQuestion(text: "Which one?", options: ["A", "B"]))
        #expect(event.agent == "my-tool")
        #expect(AgentHookEvent.validAgentName("claude") == nil)
        #expect(AgentHookEvent.validAgentName("Bad Name") == nil)
        #expect(AgentHookEvent(payload: ["hook_event_name": "Unknown"]) == nil)
    }
}

struct AgentHubStateTests {
    private let start = Date(timeIntervalSince1970: 1_000)

    private func event(_ kind: AgentHookEvent.Kind, session: String = "s1", tool: String? = nil, message: String? = nil) -> AgentHookEvent {
        var event = AgentHookEvent(kind: kind, sessionID: session, cwd: "/Users/me/deskcast")
        event.toolName = tool
        event.toolSummary = tool.map { _ in "npm test" }
        event.message = message
        return event
    }

    @Test func followsATurnFromPromptToFinish() {
        var state = AgentHubState()

        #expect(state.apply(event(.userPromptSubmit), now: start) == nil)
        #expect(state.session("s1")?.phase == .thinking)
        #expect(state.session("s1")?.title == "deskcast")

        state.apply(event(.preToolUse, tool: "Bash"), now: start.addingTimeInterval(5))
        #expect(state.session("s1")?.phase == .working)
        #expect(state.session("s1")?.currentStep?.kind == .tool("Bash"))

        let effect = state.apply(event(.stop, message: "All tests pass."), now: start.addingTimeInterval(65))
        #expect(effect == .finished(sessionID: "s1", duration: 65))
        #expect(state.session("s1")?.phase == .finished)
        #expect(state.session("s1")?.lastMessage == "All tests pass.")

        state.settle(sessionID: "s1")
        #expect(state.session("s1")?.phase == .idle)
    }

    @Test func approvalsQuestionsAndFailures() {
        var state = AgentHubState()
        state.apply(event(.permissionRequest, tool: "Bash"), now: start)
        #expect(state.session("s1")?.phase == .approval)
        #expect(state.session("s1")?.phase.needsAttention == true)
        state.resolveApproval(sessionID: "s1", now: start)
        #expect(state.session("s1")?.phase == .working)

        var question = event(.preToolUse, tool: AgentHookEvent.questionTool)
        question.question = AgentQuestion(text: "Ship it?", options: ["Yes", "No"])
        #expect(state.apply(question, now: start) == .question(sessionID: "s1"))
        #expect(state.session("s1")?.phase == .question)
        state.apply(event(.postToolUse, tool: AgentHookEvent.questionTool), now: start)
        #expect(state.session("s1")?.question == nil)

        var failure = event(.stopFailure, message: "Rate limit exceeded")
        failure.errorType = "rate_limit"
        #expect(state.apply(failure, now: start) == .rateLimited(sessionID: "s1"))
        failure.errorType = "server_error"
        #expect(state.apply(failure, now: start) == .failed(sessionID: "s1"))
    }

    @Test func keepsRecentSessionsFirstAndDropsEndedOrStaleOnes() {
        var state = AgentHubState()
        state.apply(event(.sessionStart, session: "a"), now: start)
        state.apply(event(.sessionStart, session: "b"), now: start.addingTimeInterval(1))
        #expect(state.sessions.map(\.id) == ["b", "a"])

        state.apply(event(.userPromptSubmit, session: "a"), now: start.addingTimeInterval(2))
        #expect(state.sessions.map(\.id) == ["a", "b"])

        state.apply(event(.sessionEnd, session: "a"), now: start.addingTimeInterval(3))
        #expect(state.sessions.map(\.id) == ["b"])

        state.pruneStale(now: start.addingTimeInterval(AgentHubState.staleInterval + 10))
        #expect(state.sessions.isEmpty)
    }

    @Test func keepsOnlyTheLastSteps() {
        var state = AgentHubState()
        for index in 0..<(AgentHubSession.maxSteps + 5) {
            state.apply(event(.preToolUse, tool: "Tool\(index)"), now: start)
        }
        #expect(state.session("s1")?.steps.count == AgentHubSession.maxSteps)
        #expect(state.session("s1")?.currentStep?.kind == .tool("Tool\(AgentHubSession.maxSteps + 4)"))
    }
}

struct AgentApprovalTests {
    @Test func decisionsBecomePermissionRequestOutput() throws {
        let suggestions: [[String: Any]] = [
            ["behavior": "allow", "rule": "Bash(npm *)"],
            ["behavior": "deny", "rule": "Bash(rm *)"]
        ]
        var event = AgentHookEvent(kind: .permissionRequest, sessionID: "s1")
        event.toolName = "Bash"
        event.permissionSuggestions = try JSONSerialization.data(withJSONObject: suggestions)
        let request = AgentApprovalRequest(event: event)

        func decision(_ choice: AgentApprovalDecision) throws -> [String: Any] {
            let data = Data(choice.hookOutput(for: request).utf8)
            let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            let output = try #require(object["hookSpecificOutput"] as? [String: Any])
            #expect(output["hookEventName"] as? String == "PermissionRequest")
            return try #require(output["decision"] as? [String: Any])
        }

        #expect(try decision(.allow)["behavior"] as? String == "allow")
        #expect(try decision(.deny)["behavior"] as? String == "deny")
        let always = try decision(.alwaysAllow)
        #expect(always["behavior"] as? String == "allow")
        #expect((always["updatedPermissions"] as? [[String: Any]])?.count == 1)
        #expect(request.canAlwaysAllow)
    }
}

struct ClaudeHookConfigurationTests {
    private let otherHook: [String: Any] = ["type": "command", "command": "/usr/local/bin/other-tool"]

    @Test func installKeepsOtherHooksAndRemoveTakesOnlyOurs() {
        let settings: [String: Any] = [
            "model": "opus",
            "hooks": ["Stop": [["matcher": ".*", "hooks": [otherHook]]]]
        ]

        let script = "/Users/me/Library/Application Support/DeskCast/bin/deskcast-hook"
        let installed = ClaudeHookConfiguration.installing(into: settings, scriptPath: script, approvalTimeout: 110)
        #expect(ClaudeHookConfiguration.isInstalled(in: installed))
        #expect(ClaudeHookConfiguration.installedApprovalTimeout(in: installed) == 120)
        #expect(installed["model"] as? String == "opus")
        let stop = (installed["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]]
        #expect(stop?.count == 2)

        // Installing again replaces DeskCast's entries instead of adding more.
        let again = ClaudeHookConfiguration.installing(into: installed, scriptPath: "/x/deskcast-hook", approvalTimeout: 60)
        #expect(((again["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])?.count == 2)
        #expect(ClaudeHookConfiguration.installedApprovalTimeout(in: again) == 70)

        let removed = ClaudeHookConfiguration.removing(from: again)
        #expect(!ClaudeHookConfiguration.isInstalled(in: removed))
        let hooks = removed["hooks"] as? [String: Any]
        #expect(hooks?.keys.sorted() == ["Stop"])
        #expect(((hooks?["Stop"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])?.count == 1)
    }

    @Test func removingFromAnEmptyFileLeavesItEmpty() {
        #expect(ClaudeHookConfiguration.removing(from: [:]).isEmpty)
        #expect(!ClaudeHookConfiguration.isInstalled(in: [:]))
        #expect(ClaudeHookConfiguration.command(scriptPath: "/a b/deskcast-hook") == "\"/a b/deskcast-hook\"")
    }

    @Test func diffShowsOnlyRealChanges() {
        let diff = ClaudeHookInstallService.lineDiff(from: "{\"a\": 1}", to: "{\n  \"a\" : 1,\n  \"b\" : 2\n}\n")
        #expect(diff.contains("+   \"b\" : 2"))
        #expect(ClaudeHookInstallService.lineDiff(from: "{\"a\": 1}", to: "{\n  \"a\" : 1\n}").isEmpty)
    }
}
