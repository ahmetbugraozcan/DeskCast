import CoreServices
import Foundation

/// Reports Claude Code and Codex turns in progress. Callbacks arrive on the
/// main actor.
nonisolated protocol AgentActivityProviding: AnyObject {
    var onUpdate: (@MainActor @Sendable ([AgentSession]) -> Void)? { get set }
    /// A turn ended normally (not interrupted), with how long it ran.
    var onFinish: (@MainActor @Sendable (AgentSession, TimeInterval) -> Void)? { get set }
    func start()
    func stop()
}

/// Watches `~/.claude/projects` and `~/.codex/sessions` with FSEvents and
/// reads each changed transcript from where it left off, so only new lines
/// are parsed. A turn whose transcript hasn't changed for half an hour
/// (e.g. the agent was killed) no longer counts as working.
nonisolated final class AgentActivityService: AgentActivityProviding, @unchecked Sendable {
    var onUpdate: (@MainActor @Sendable ([AgentSession]) -> Void)?
    var onFinish: (@MainActor @Sendable (AgentSession, TimeInterval) -> Void)?

    private struct Transcript {
        var state: AgentTranscriptState
        var offset: UInt64
        var partialLine = Data()
        var lastWrite: Date
    }

    private let roots: [(url: URL, kind: AgentKind)]
    private let queue = DispatchQueue(label: "com.deskcast.agent-activity", qos: .utility)
    // Everything below is confined to `queue`.
    private var stream: FSEventStreamRef?
    private var sweepTimer: DispatchSourceTimer?
    private var transcripts: [String: Transcript] = [:]
    private var published: [AgentSession] = []
    private var isRunning = false

    static let staleAfter: TimeInterval = 30 * 60
    /// On start, transcripts written this recently are read from their tail.
    private static let initialTailBytes: UInt64 = 512 * 1024

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        roots = [
            (home.appendingPathComponent(".claude/projects", isDirectory: true), .claude),
            (home.appendingPathComponent(".codex/sessions", isDirectory: true), .codex)
        ]
    }

    deinit {
        stopStream()
        sweepTimer?.cancel()
    }

    func start() {
        queue.async { [self] in
            guard !isRunning else { return }
            isRunning = true
            loadRecentTranscripts()
            startStream()
            startSweep()
            publish()
        }
    }

    func stop() {
        queue.async { [self] in
            guard isRunning else { return }
            isRunning = false
            stopStream()
            sweepTimer?.cancel()
            sweepTimer = nil
            transcripts = [:]
            publish()
        }
    }

    // MARK: - Reading

    private func loadRecentTranscripts() {
        let cutoff = Date().addingTimeInterval(-Self.staleAfter)
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]

        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root.url,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for case let url as URL in enumerator where Self.isTranscript(url.path) {
                guard let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true,
                      let modified = values.contentModificationDate,
                      modified > cutoff else {
                    continue
                }

                let size = UInt64(values.fileSize ?? 0)
                let start = size > Self.initialTailBytes ? size - Self.initialTailBytes : 0
                var transcript = Transcript(state: AgentTranscriptState(kind: root.kind), offset: start, lastWrite: modified)
                // Past lines only restore state; their endings aren't news.
                read(url.path, into: &transcript, startsMidLine: start > 0, announces: false)
                transcripts[url.path] = transcript
            }
        }
    }

    private func handleChanges(_ paths: [String]) {
        guard isRunning else { return }

        for path in Set(paths) where Self.isTranscript(path) {
            guard let kind = kind(of: path) else { continue }
            var transcript = transcripts[path]
                ?? Transcript(state: AgentTranscriptState(kind: kind), offset: 0, lastWrite: Date())
            transcript.lastWrite = Date()
            read(path, into: &transcript, startsMidLine: false, announces: true)
            transcripts[path] = transcript
        }

        publish()
    }

    private func read(_ path: String, into transcript: inout Transcript, startsMidLine: Bool, announces: Bool) {
        guard let handle = FileHandle(forReadingAtPath: path) else { return }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        if size < transcript.offset {
            // Rewritten from scratch.
            transcript = Transcript(state: AgentTranscriptState(kind: transcript.state.kind), offset: 0, lastWrite: transcript.lastWrite)
        }

        guard size > transcript.offset,
              (try? handle.seek(toOffset: transcript.offset)) != nil,
              let data = try? handle.readToEnd() else {
            return
        }

        transcript.offset += UInt64(data.count)
        var buffer = transcript.partialLine + data
        var lines = buffer.split(separator: 0x0A, omittingEmptySubsequences: false)
        // The last piece has no newline yet; keep it for the next read.
        buffer = lines.popLast().map(Data.init) ?? Data()
        transcript.partialLine = buffer.count <= AgentTranscriptState.maxParsedLineLength ? buffer : Data()

        if startsMidLine, !lines.isEmpty {
            lines.removeFirst()
        }

        for line in lines {
            let session = transcript.state.turnStartedAt.map {
                AgentSession(id: path, kind: transcript.state.kind, project: transcript.state.project, startedAt: $0)
            }
            let transition = transcript.state.consume(Data(line))

            if announces, case .finished(let duration) = transition, let session, !transcript.state.isSubthread {
                let onFinish = onFinish
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { onFinish?(session, duration) }
                }
            }
        }
    }

    private func publish() {
        let now = Date()
        let sessions = transcripts.compactMap { path, transcript -> AgentSession? in
            guard isRunning,
                  transcript.state.isWorking,
                  !transcript.state.isSubthread,
                  now.timeIntervalSince(transcript.lastWrite) < Self.staleAfter,
                  let startedAt = transcript.state.turnStartedAt else {
                return nil
            }
            return AgentSession(id: path, kind: transcript.state.kind, project: transcript.state.project, startedAt: startedAt)
        }
        .sorted { $0.startedAt < $1.startedAt }

        guard sessions != published else { return }
        published = sessions

        let onUpdate = onUpdate
        DispatchQueue.main.async {
            MainActor.assumeIsolated { onUpdate?(sessions) }
        }
    }

    /// Drops stale turns and forgets idle transcripts nobody wrote to lately.
    private func startSweep() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 60, repeating: 60, leeway: .seconds(10))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let cutoff = Date().addingTimeInterval(-Self.staleAfter)
            transcripts = transcripts.filter { $0.value.lastWrite > cutoff }
            publish()
        }
        timer.resume()
        sweepTimer = timer
    }

    // MARK: - FSEvents

    private func startStream() {
        let paths = roots.map(\.url.path).filter { FileManager.default.fileExists(atPath: $0) }
        guard !paths.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
            guard let info else { return }
            let service = Unmanaged<AgentActivityService>.fromOpaque(info).takeUnretainedValue()
            let array = unsafeBitCast(eventPaths, to: NSArray.self)
            let paths = (0..<count).compactMap { array[$0] as? String }
            service.handleChanges(paths)
        }
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            flags
        ) else {
            return
        }

        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    private func stopStream() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func kind(of path: String) -> AgentKind? {
        roots.first { path.hasPrefix($0.url.path + "/") }?.kind
    }

    /// Top-level session transcripts; Claude Code's sub-agents live in
    /// `subagents/` folders and are part of their parent's turn.
    private static func isTranscript(_ path: String) -> Bool {
        path.hasSuffix(".jsonl") && !path.contains("/subagents/")
    }
}
