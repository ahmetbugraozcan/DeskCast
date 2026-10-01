import CoreGraphics
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

struct ClaudeChatProtocolTests {
    @Test func requestUsesTheRightSearchToolAndFallbacks() {
        let current = ClaudeChatProtocol.body(model: "claude-opus-5-5", messages: [])
        #expect((current["tools"] as? [[String: Any]])?.first?["type"] as? String == "web_search_20260209")
        #expect(current["fallbacks"] as? String == "default")

        let older = ClaudeChatProtocol.body(model: "claude-haiku-4-5", messages: [])
        #expect((older["tools"] as? [[String: Any]])?.first?["type"] as? String == "web_search_20250305")
        #expect(older["fallbacks"] == nil)
    }

    @Test func attachmentsBecomeContentBlocks() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let text = folder.appendingPathComponent("notes.md")
        try Data("# Hello".utf8).write(to: text)
        let blocks = try ClaudeChatProtocol.userContent(question: "Summarize", attachment: .file(text))
        #expect(blocks.count == 3)
        #expect((blocks[0]["text"] as? String)?.contains("# Hello") == true)
        #expect(blocks.last?["text"] as? String == "Summarize")

        let image = folder.appendingPathComponent("shot.png")
        try Data([0x89, 0x50]).write(to: image)
        let imageBlock = try ClaudeChatProtocol.fileBlock(image)
        #expect(imageBlock["type"] as? String == "image")
        #expect((imageBlock["source"] as? [String: Any])?["media_type"] as? String == "image/png")

        let binary = folder.appendingPathComponent("blob.bin")
        try Data([0xFF, 0xFE, 0x00, 0xD8]).write(to: binary)
        #expect(throws: ClaudeChatError.unsupportedFile("blob.bin")) {
            try ClaudeChatProtocol.fileBlock(binary)
        }

        let window = AgentWindowContext(appName: "Safari", title: "Docs", url: "https://example.com/a", image: Data([1]), frame: .zero)
        #expect(window.label == "Safari · example.com")
        let windowBlocks = try ClaudeChatProtocol.userContent(question: "What is this?", attachment: .window(window))
        #expect(windowBlocks.first?["type"] as? String == "image")
        #expect((windowBlocks[1]["text"] as? String)?.contains("https://example.com/a") == true)
    }

    @Test func readsTextSourcesAndRefusals() throws {
        let response: [String: Any] = [
            "stop_reason": "end_turn",
            "content": [
                ["type": "thinking", "thinking": "", "signature": "x"],
                ["type": "server_tool_use", "id": "1", "name": "web_search", "input": ["query": "q"]],
                ["type": "web_search_tool_result", "tool_use_id": "1", "content": [
                    ["type": "web_search_result", "title": "A", "url": "https://a.com"],
                    ["type": "web_search_result", "title": "A again", "url": "https://a.com"]
                ]],
                ["type": "text", "text": "Hello "],
                ["type": "text", "text": "world"]
            ]
        ]
        let reply = try ClaudeChatProtocol.parseReply(JSONSerialization.data(withJSONObject: response))
        #expect(reply.text == "Hello world")
        #expect(reply.sources == [AgentChatSource(title: "A", url: "https://a.com")])
        let content = try #require(try JSONSerialization.jsonObject(with: reply.content) as? [[String: Any]])
        #expect(content.count == 5)

        let refusal = try JSONSerialization.data(withJSONObject: ["stop_reason": "refusal", "content": []])
        #expect(throws: ClaudeChatError.refused) { try ClaudeChatProtocol.parseReply(refusal) }
    }

    @Test func readsErrorsAndModels() throws {
        let body: [String: Any] = ["type": "error", "error": ["type": "invalid_request_error", "message": "Bad input"]]
        let error = try JSONSerialization.data(withJSONObject: body)
        #expect(ClaudeChatProtocol.errorMessage(error, status: 400, model: "m") == "Bad input")

        let models = try JSONSerialization.data(withJSONObject: ["data": [["id": "claude-opus-5-5", "display_name": "Claude Opus 5.5"]]])
        #expect(ClaudeChatProtocol.parseModels(models).first?.name == "Claude Opus 5.5")
    }

    @Test func mailAddressesAreChecked() {
        #expect(MailSendService.isValidAddress("me@example.com"))
        #expect(!MailSendService.isValidAddress("me@example"))
        #expect(!MailSendService.isValidAddress("me @example.com"))
        #expect(!MailSendService.isValidAddress("@example.com"))
    }
}

struct ClaudeCodeChatProtocolTests {
    @Test func runsReadOnlyWithoutTheUsersSettingsAndResumes() {
        let first = ClaudeCodeChatProtocol.arguments(prompt: "Hi", resume: nil, extraFolders: [])
        #expect(Array(first.prefix(2)) == ["-p", "Hi"])
        #expect(first.contains("--strict-mcp-config"))
        #expect(!first.contains("--resume"))
        let tools = first.firstIndex(of: "--tools").map { first[$0 + 1] }
        #expect(tools == "Read,WebSearch,WebFetch")
        let sources = first.firstIndex(of: "--setting-sources").map { first[$0 + 1] }
        #expect(sources == "project")

        let next = ClaudeCodeChatProtocol.arguments(prompt: "And?", resume: "abc", extraFolders: ["/Users/me/Docs"])
        #expect(next.firstIndex(of: "--resume").map { next[$0 + 1] } == "abc")
        #expect(next.firstIndex(of: "--add-dir").map { next[$0 + 1] } == "/Users/me/Docs")
    }

    @Test func promptNamesTheAttachment() {
        let file = ClaudeCodeChatProtocol.prompt(
            question: "Summarize",
            attachment: .file(URL(fileURLWithPath: "/Users/me/Docs/a.pdf")),
            windowImagePath: nil
        )
        #expect(file == "Attached file: /Users/me/Docs/a.pdf\n\nSummarize")

        let context = AgentWindowContext(appName: "Safari", title: "News", url: "https://example.com", image: nil, frame: .zero)
        let window = ClaudeCodeChatProtocol.prompt(question: "What's this?", attachment: .window(context), windowImagePath: "/tmp/w.jpg")
        #expect(window.contains("app: Safari, title: News, URL: https://example.com"))
        #expect(window.contains("Screenshot of the window: /tmp/w.jpg"))
        #expect(ClaudeCodeChatProtocol.prompt(question: "Hi", attachment: nil, windowImagePath: nil) == "Hi")
    }

    @Test func readsResultsAndErrors() throws {
        let ok = Data(#"{"type":"result","subtype":"success","is_error":false,"result":" 4 ","session_id":"s1"}"#.utf8)
        #expect(try ClaudeCodeChatProtocol.parseReply(ok) == ClaudeCodeReply(text: "4", sessionID: "s1"))

        let loggedOut = Data(#"{"type":"result","is_error":true,"result":"Not logged in · Please run /login"}"#.utf8)
        #expect(throws: ClaudeChatError.api(AppLocalization.string("agentHub.ask.error.claudeLogin"))) {
            try ClaudeCodeChatProtocol.parseReply(loggedOut)
        }
        #expect(throws: ClaudeChatError.self) { try ClaudeCodeChatProtocol.parseReply(Data("oops".utf8)) }
    }

    @Test func skipsDeskCastsOwnTranscripts() {
        let ask = "/Users/me/.claude/projects/-Users-me-Library-Application-Support-DeskCast-DeskCast-Ask/s.jsonl"
        #expect(ClaudeCodeChatProtocol.isAskTranscript(ask))
        #expect(!ClaudeCodeChatProtocol.isAskTranscript("/Users/me/.claude/projects/-Users-me-Projects-app/s.jsonl"))
    }
}

struct CodexHookTests {
    @Test func installsTaggedHooksNextToOtherToolsInCodexHooksFile() throws {
        let other: [String: Any] = ["hooks": ["Stop": [["matcher": ".*", "hooks": [["type": "command", "command": "other-tool"]]]]]]
        let installed = ClaudeHookConfiguration.installing(
            into: other, scriptPath: "/x/deskcast-hook", approvalTimeout: 110, target: .codex
        )

        #expect(ClaudeHookConfiguration.isInstalled(in: installed, target: .codex))
        #expect(ClaudeHookConfiguration.installedApprovalTimeout(in: installed) == 120)
        let hooks = try #require(installed["hooks"] as? [String: Any])
        #expect(hooks["Notification"] == nil)
        #expect(hooks["Interrupt"] != nil)
        let stop = try #require(hooks["Stop"] as? [[String: Any]])
        #expect(stop.count == 2)
        let ours = try #require(stop.last)
        #expect(ours["matcher"] as? String == ".*")
        let command = (ours["hooks"] as? [[String: Any]])?.first?["command"] as? String
        #expect(command == "\"/x/deskcast-hook\" --agent codex")

        let removed = ClaudeHookConfiguration.removing(from: installed)
        #expect((removed["hooks"] as? [String: Any])?.keys.sorted() == ["Stop"])
    }

    @Test func codexEventsBecomeACodexSession() throws {
        let patch = "*** Begin Patch\n*** Update File: Sources/App.swift\n@@\n-a\n+b\n*** Add File: README.md\n+hi\n*** End Patch"
        let event = try #require(AgentHookEvent(payload: [
            "hook_event_name": "PreToolUse",
            "session_id": "c1",
            "cwd": "/Users/me/Projects/deskcast",
            "tool_name": "apply_patch",
            "tool_input": ["command": patch],
            "deskcast_agent": "codex"
        ]))
        #expect(event.agent == "codex")
        #expect(event.toolSummary == "App.swift, README.md")

        var state = AgentHubState()
        _ = state.apply(event)
        #expect(state.session("c1")?.title == "Codex · deskcast")
        #expect(state.session("c1")?.phase == .working)

        let interrupt = try #require(AgentHookEvent(payload: [
            "hook_event_name": "Interrupt", "session_id": "c1", "deskcast_agent": "codex"
        ]))
        _ = state.apply(interrupt)
        #expect(state.session("c1")?.phase == .idle)
    }
}

struct AgentCodeChangeTests {
    private let file = """
    import { Item } from './types'

    const TVA = 0.196

    export function total(items: Item[]) {
      const sum = items.reduce((s, i) => s + i.price, 0)
      return sum * (1 + TVA)
    }
    """

    @Test func numbersAnEditFromTheFileWithContext() throws {
        let change = try #require(AgentCodeChange.make(
            tool: "Edit",
            input: ["file_path": "/p/src/invoice.ts", "old_string": "const TVA = 0.196", "new_string": "const TVA = 0.20"],
            fileText: file
        ))

        #expect(change.fileName == "invoice.ts")
        #expect(change.lines.map(\.kind) == [.context, .context, .removed, .added, .context, .context])
        #expect(change.lines[2] == AgentCodeLine(kind: .removed, number: 3, text: "const TVA = 0.196"))
        #expect(change.lines[3] == AgentCodeLine(kind: .added, number: 3, text: "const TVA = 0.20"))
        #expect(change.lines.first?.number == 1)
        #expect(change.addedCount == 1 && change.removedCount == 1)
    }

    @Test func keepsSharedLinesAsContextAndWorksWithoutTheFile() throws {
        let change = try #require(AgentCodeChange.edit(path: "a.swift", old: "a\nb\nc", new: "a\nB\nc", fileText: nil))
        #expect(change.lines.map(\.kind) == [.context, .removed, .added, .context])
        #expect(change.lines.allSatisfy { $0.number == nil })
        #expect(AgentCodeChange.edit(path: "a.swift", old: "same", new: "same", fileText: nil) == nil)
    }

    @Test func showsNewFilesAndCodexPatches() throws {
        let write = try #require(AgentCodeChange.make(
            tool: "Write", input: ["file_path": "/p/new.md", "content": "# Hi\n\nText\n"], fileText: nil
        ))
        #expect(write.lines.map(\.number) == [1, 2, 3])
        #expect(write.lines.allSatisfy { $0.kind == .added })

        let patch = "*** Begin Patch\n*** Update File: src/App.swift\n@@ func run()\n let a = 1\n-print(a)\n+print(a + 1)\n"
            + "*** Update File: other.swift\n+x\n*** End Patch"
        let change = try #require(AgentCodeChange.make(tool: "apply_patch", input: ["command": patch], fileText: nil))
        #expect(change.fileName == "App.swift")
        #expect(change.lines.map(\.kind) == [.context, .removed, .added])
        #expect(change.lines[2].text == "print(a + 1)")
    }

    @Test func longChangesKeepTheChangeInView() throws {
        let old = (1...30).map { "line \($0)" }.joined(separator: "\n")
        let new = (1...30).map { $0 == 20 ? "changed" : "line \($0)" }.joined(separator: "\n")
        let change = try #require(AgentCodeChange.edit(path: "a.txt", old: old, new: new, fileText: nil))
        #expect(change.lines.map(\.text) == ["line 18", "line 19", "line 20", "changed", "line 21", "line 22"])

        let big = (1...40).map { "new \($0)" }.joined(separator: "\n")
        let rewrite = try #require(AgentCodeChange.edit(path: "a.txt", old: "x", new: big, fileText: nil))
        #expect(rewrite.lines.count == AgentCodeChange.maxLines)
        #expect(rewrite.lines.first?.kind == .removed)
    }

    @Test func commandOutputKeepsTheLastLinesWithoutColors() {
        let response: [String: Any] = ["stdout": "\u{1B}[32mPASS\u{1B}[0m tests/a.test.ts\n\nTests: 48 passed, 48 total\n", "stderr": ""]
        #expect(AgentCommandRun.outputLines(from: response) == ["PASS tests/a.test.ts", "Tests: 48 passed, 48 total"])
        #expect(AgentCommandRun.outputLines(from: "a\nb\nc\nd\ne") == ["b", "c", "d", "e"])
        #expect(AgentCommandRun.outputLines(from: nil).isEmpty)
    }

    @Test func sessionFollowsEditsAndCommands() throws {
        var state = AgentHubState()
        func apply(_ payload: [String: Any]) throws {
            var payload = payload
            payload["session_id"] = "s1"
            _ = state.apply(try #require(AgentHookEvent(payload: payload)))
        }

        try apply(["hook_event_name": "UserPromptSubmit", "prompt": "Fix tax"])
        try apply(["hook_event_name": "PreToolUse", "tool_name": "Edit",
                   "tool_input": ["file_path": "/nonexistent/x.ts", "old_string": "a", "new_string": "b"]])
        #expect(state.session("s1")?.codeChange?.fileName == "x.ts")
        #expect(state.session("s1")?.showsCommand == false)

        try apply(["hook_event_name": "PreToolUse", "tool_name": "Bash", "tool_input": ["command": "npm test"]])
        #expect(state.session("s1")?.command == AgentCommandRun(command: "npm test"))
        try apply(["hook_event_name": "PostToolUse", "tool_name": "Bash", "tool_input": ["command": "npm test"],
                   "tool_response": ["stdout": "ok\nTests: 2 passed"]])
        #expect(state.session("s1")?.command?.output == ["ok", "Tests: 2 passed"])
        #expect(state.session("s1")?.showsCommand == true)
        #expect(state.session("s1")?.turnSteps.count == 2)

        try apply(["hook_event_name": "UserPromptSubmit", "prompt": "Next"])
        #expect(state.session("s1")?.codeChange == nil)
        #expect(state.session("s1")?.command == nil)
        #expect(state.session("s1")?.turnSteps.isEmpty == true)
    }
}
