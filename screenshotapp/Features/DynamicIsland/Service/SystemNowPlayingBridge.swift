import Foundation
import OSLog

/// Reads the system-wide now playing session (browsers, Podcasts, Music,
/// Spotify, …) and sends transport commands to it.
///
/// Since macOS 15.4 MediaRemote only answers Apple platform binaries, so the
/// bundled `libDeskCastNowPlaying.dylib` (built from `NowPlayingAdapter/`) is
/// loaded into `/usr/bin/perl`, which streams one JSON line per change.
@MainActor
final class SystemNowPlayingBridge {
    /// Latest session, or `nil` when nothing is loaded. Delivered on the main actor.
    var onChange: ((MediaPlayerTrackSnapshot?) -> Void)?

    private(set) var isAvailable: Bool
    private var process: Process?
    private var inputPipe: Pipe?
    /// One-shot command processes, kept alive until they exit so they're reaped.
    private var commandProcesses: Set<Process> = []
    private var restartTask: Task<Void, Never>?
    private var quickFailures = 0
    private var startedAt = Date()
    private var isRunning = false
    /// Artwork is only sent when it changes; later lines reuse these bytes.
    private var artwork: (hash: String, data: Data)?

    private static let perlURL = URL(fileURLWithPath: "/usr/bin/perl")
    private static let maxQuickFailures = 4
    private static let logger = Logger(subsystem: "com.ahmetbugraozcan.screenshotapp", category: "NowPlayingBridge")

    /// Loads the adapter into perl and calls `deskcast_now_playing_<mode>`,
    /// which prints JSON and exits; it never returns to perl.
    private static let loaderScript = """
    use strict; use DynaLoader;
    my ($library, $mode) = @ARGV;
    my $handle = DynaLoader::dl_load_file($library, 0) or die DynaLoader::dl_error() . "\\n";
    my $symbol = DynaLoader::dl_find_symbol($handle, "deskcast_now_playing_$mode") or die DynaLoader::dl_error() . "\\n";
    DynaLoader::dl_install_xsub("main::deskcast_run", $symbol);
    deskcast_run();
    """

    private static var adapterURL: URL? {
        guard let url = Bundle.main.privateFrameworksURL?.appendingPathComponent("libDeskCastNowPlaying.dylib"),
              FileManager.default.fileExists(atPath: url.path),
              FileManager.default.isExecutableFile(atPath: perlURL.path) else {
            return nil
        }

        return url
    }

    init() {
        isAvailable = Self.adapterURL != nil
    }

    func start() {
        guard isAvailable, !isRunning else { return }
        isRunning = true
        quickFailures = 0
        launchWatcher()
    }

    func stop() {
        isRunning = false
        restartTask?.cancel()
        restartTask = nil
        terminateWatcher()
        artwork = nil
    }

    /// Asks the watcher to re-send the full state (e.g. when the island opens).
    func refresh() {
        guard let inputPipe else { return }
        try? inputPipe.fileHandleForWriting.write(contentsOf: Data("refresh\n".utf8))
    }

    func send(_ command: MediaCommand) {
        // MRCommand values: 2 = toggle play/pause, 4 = next, 5 = previous.
        let value = switch command {
        case .togglePlayPause: 2
        case .nextTrack: 4
        case .previousTrack: 5
        }

        runOnce(environment: ["DESKCAST_NP_COMMAND": String(value)])
    }

    func seek(to seconds: TimeInterval) {
        runOnce(environment: ["DESKCAST_NP_SEEK": String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), max(seconds, 0))])
    }

    // MARK: - Processes

    private func makeProcess(mode: String) -> Process? {
        guard let adapterURL = Self.adapterURL else { return nil }

        let process = Process()
        process.executableURL = Self.perlURL
        process.arguments = ["-e", Self.loaderScript, adapterURL.path, mode]
        return process
    }

    private func runOnce(environment: [String: String]) {
        guard let process = makeProcess(mode: "send") else { return }

        process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] finished in
            Task { @MainActor in
                self?.commandProcesses.remove(finished)
            }
        }

        do {
            try process.run()
            commandProcesses.insert(process)
        } catch {
            Self.logger.error("Command failed to launch: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func launchWatcher() {
        guard isRunning, let process = makeProcess(mode: "watch") else { return }

        let output = Pipe()
        let input = Pipe()
        process.standardOutput = output
        process.standardInput = input
        process.standardError = FileHandle.nullDevice

        let reader = LineReader()
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }

            let states = reader.append(data).compactMap(Self.decode)
            guard !states.isEmpty else { return }

            Task { @MainActor in
                states.forEach { self?.apply($0) }
            }
        }

        process.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus

            Task { @MainActor in
                self?.watcherExited(finished, status: status)
            }
        }

        do {
            startedAt = Date()
            try process.run()
            self.process = process
            inputPipe = input
        } catch {
            Self.logger.error("Watcher failed to launch: \(error.localizedDescription, privacy: .public)")
            output.fileHandleForReading.readabilityHandler = nil
            isAvailable = false
            onChange?(nil)
        }
    }

    private func terminateWatcher() {
        guard let process else { return }

        self.process = nil
        // Closing stdin makes the adapter exit on its own; terminate as backup.
        try? inputPipe?.fileHandleForWriting.close()
        inputPipe = nil
        if process.isRunning {
            process.terminate()
        }
    }

    private func watcherExited(_ finished: Process, status: Int32) {
        guard finished === process else { return }

        process = nil
        inputPipe = nil
        guard isRunning else { return }

        Self.logger.error("Watcher exited with status \(status, privacy: .public)")

        quickFailures = Date().timeIntervalSince(startedAt) < 10 ? quickFailures + 1 : 0
        guard quickFailures < Self.maxQuickFailures else {
            // The adapter can't run here; fall back to the scripted players.
            isAvailable = false
            onChange?(nil)
            return
        }

        restartTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.launchWatcher()
        }
    }

    // MARK: - Parsing

    private func apply(_ state: BridgeState) {
        guard isRunning else { return }

        if let hash = state.artworkHash {
            if let encoded = state.artwork, let data = Data(base64Encoded: encoded) {
                artwork = (hash, data)
            }
        } else {
            artwork = nil
        }

        let title = state.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let artist = state.artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let bundle = state.parent?.isEmpty == false ? state.parent : state.bundle

        guard let bundle, !title.isEmpty || !artist.isEmpty else {
            onChange?(nil)
            return
        }

        let artworkData = artwork.flatMap { $0.hash == state.artworkHash ? $0.data : nil }

        onChange?(
            MediaPlayerTrackSnapshot(
                source: NowPlayingSource(bundleIdentifier: bundle),
                trackID: "\(title)|\(artist)|\(state.album ?? "")",
                title: title,
                artist: artist,
                album: state.album ?? "",
                duration: state.duration ?? 0,
                elapsed: state.elapsed ?? 0,
                isPlaying: state.playing ?? false,
                artworkURL: nil,
                artworkData: artworkData,
                capabilities: state.capabilities
            )
        )
    }

    nonisolated private static func decode(_ line: Data) -> BridgeState? {
        try? JSONDecoder().decode(BridgeState.self, from: line)
    }
}

nonisolated private struct BridgeState: Decodable, Sendable {
    let bundle: String?
    let parent: String?
    let playing: Bool?
    let title: String?
    let artist: String?
    let album: String?
    let duration: Double?
    let elapsed: Double?
    let artworkHash: String?
    let artwork: String?
    /// Enabled MRCommand numbers; missing on adapters that can't read them.
    let commands: [Int]?

    var capabilities: NowPlayingCapabilities {
        guard let commands else { return .all }
        let enabled = Set(commands)
        return NowPlayingCapabilities(
            canSkip: enabled.contains(4),
            canGoBack: enabled.contains(5),
            canSeek: enabled.contains(24)
        )
    }
}

/// Splits the adapter's stdout into lines; only touched from the pipe's
/// readability handler, which never runs concurrently with itself.
nonisolated private final class LineReader: @unchecked Sendable {
    private var buffer = Data()

    func append(_ data: Data) -> [Data] {
        buffer.append(data)
        var lines: [Data] = []

        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = buffer[buffer.startIndex..<newline]
            if !line.isEmpty {
                lines.append(Data(line))
            }
            buffer.removeSubrange(buffer.startIndex...newline)
        }

        return lines
    }
}
