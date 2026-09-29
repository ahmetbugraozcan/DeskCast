import CoreServices
import Foundation
import OSLog

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
/// are parsed. FSEvents reports content changes only when a file is closed,
/// and Codex keeps its transcript open while it writes, so Codex transcripts
/// are polled as well. A turn whose transcript hasn't changed for half an hour
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
    private var pollTimer: DispatchSourceTimer?
    private var pollCount = 0
    private var transcripts: [String: Transcript] = [:]
    private var published: [AgentSession] = []
    private var isRunning = false

    private static let logger = Logger(subsystem: "com.ahmetbugraozcan.screenshotapp", category: "AgentActivity")

    static let staleAfter: TimeInterval = 30 * 60
    /// On start, transcripts written this recently are read from their tail,
    /// growing it until a prompt or a turn's end shows up (Codex can write
    /// megabytes of tool output within one turn).
    private static let initialTailBytes: UInt64 = 512 * 1024
    private static let maxInitialTailBytes: UInt64 = 32 * 1024 * 1024
    private static let pollInterval: TimeInterval = 2
    /// Every this many polls, looks for Codex transcripts written to again
    /// (a resumed thread appends to its original, older file).
    private static let pollsPerDiscovery = 5

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        roots = [
            (home.appendingPathComponent(".claude/projects", isDirectory: true), .claude),
            (home.appendingPathComponent(".codex/sessions", isDirectory: true), .codex)
        ]
    }

    deinit {
        stopStream()
        sweepTimer?.cancel()
        pollTimer?.cancel()
    }

    func start() {
        queue.async { [self] in
            guard !isRunning else { return }
            isRunning = true
            loadRecentTranscripts()
            startStream()
            startSweep()
            startPolling()
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
            pollTimer?.cancel()
            pollTimer = nil
            transcripts = [:]
            publish()
        }
    }

    // MARK: - Reading

    private func loadRecentTranscripts() {
        for root in roots {
            loadRecentTranscripts(in: root, skippingKnown: false)
        }
    }

    private func loadRecentTranscripts(in root: (url: URL, kind: AgentKind), skippingKnown: Bool) {
        let cutoff = Date().addingTimeInterval(-Self.staleAfter)
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]

        guard let enumerator = FileManager.default.enumerator(
            at: root.url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for case let url as URL in enumerator where Self.isTranscript(url.path) {
            if skippingKnown, transcripts[url.path] != nil { continue }

            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate,
                  modified > cutoff else {
                continue
            }

            let size = UInt64(values.fileSize ?? 0)
            var tail = Self.initialTailBytes

            while true {
                let start = size > tail ? size - tail : 0
                var transcript = Transcript(state: AgentTranscriptState(kind: root.kind), offset: start, lastWrite: modified)
                // Past lines only restore state; their endings aren't news.
                read(url.path, into: &transcript, startsMidLine: start > 0, announces: false)
                transcripts[url.path] = transcript

                guard !transcript.state.hasSeenTurnBoundary, start > 0, tail < Self.maxInitialTailBytes else { break }
                tail *= 4
            }
        }
    }

    /// Reads Codex transcripts that grew since the last read.
    private func pollCodex() {
        guard isRunning else { return }

        pollCount += 1
        if pollCount.isMultiple(of: Self.pollsPerDiscovery) {
            for root in roots where root.kind == .codex {
                loadRecentTranscripts(in: root, skippingKnown: true)
            }
        }

        for (path, known) in transcripts where known.state.kind == .codex {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                  let size = (attributes[.size] as? NSNumber)?.uint64Value,
                  size != known.offset else {
                continue
            }

            var transcript = known
            transcript.lastWrite = attributes[.modificationDate] as? Date ?? Date()
            read(path, into: &transcript, startsMidLine: false, announces: true)
            transcripts[path] = transcript
        }

        publish()
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
        buffer = lines.popLast().map { Data($0) } ?? Data()
        transcript.partialLine = buffer.count <= AgentTranscriptState.maxParsedLineLength ? buffer : Data()

        if startsMidLine, !lines.isEmpty {
            lines.removeFirst()
        }

        for line in lines {
            let session = transcript.state.turnStartedAt.map {
                AgentSession(id: path, kind: transcript.state.kind, project: transcript.state.project, startedAt: $0)
            }
            let transition = transcript.state.consume(Data(line))

            if announces, let transition {
                let kind = transcript.state.kind.rawValue
                let change = String(describing: transition)
                Self.logger.info("\(kind, privacy: .public) \(change, privacy: .public)")
            }

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

    private func startPolling() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.pollInterval, repeating: Self.pollInterval, leeway: .milliseconds(500))
        timer.setEventHandler { [weak self] in
            self?.pollCodex()
        }
        timer.resume()
        pollTimer = timer
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
