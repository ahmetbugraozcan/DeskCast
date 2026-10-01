import Darwin
import Foundation

/// Hook calls arriving from the relay.
@MainActor
protocol AgentHookServing: AnyObject {
    /// Every hook event except permission requests.
    var onEvent: ((AgentHookEvent) -> Void)? { get set }
    /// A permission request; Claude Code waits until `reply` is called. An
    /// empty reply lets Claude Code ask in the terminal instead.
    var onPermissionRequest: ((AgentHookEvent, _ reply: @escaping (String) -> Void) -> Void)? { get set }
    func start()
    func stop()
}

/// Listens on a Unix socket (owner-only, same user checked with
/// `getpeereid`) for newline-delimited JSON from the relay. Socket work runs
/// on background threads; callbacks arrive on the main actor.
final class AgentHookServer: AgentHookServing {
    var onEvent: ((AgentHookEvent) -> Void)?
    var onPermissionRequest: ((AgentHookEvent, _ reply: @escaping (String) -> Void) -> Void)?

    private let listener = Listener()

    func start() {
        guard !listener.isRunning else { return }

        listener.handler = { [weak self] payload, reply in
            let box = PayloadBox(payload: payload)
            Task { @MainActor [weak self] in
                self?.handle(box.payload, reply: reply)
            }
        }
        listener.start(path: AgentHookPaths.socket.path)
    }

    func stop() {
        listener.stop()
    }

    private func handle(_ payload: [String: Any], reply: @escaping @Sendable (String) -> Void) {
        guard let event = AgentHookEvent(payload: payload) else {
            reply("")
            return
        }

        if event.kind == .permissionRequest, let onPermissionRequest {
            onPermissionRequest(event) { reply($0) }
        } else {
            reply("")
            onEvent?(event)
        }
    }
}

/// Hands a decoded JSON object (only read afterwards) to the main actor.
nonisolated private struct PayloadBox: @unchecked Sendable {
    let payload: [String: Any]
}

/// Lets only the first reply through; the connection is closed after it.
nonisolated private final class ReplyOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var isClaimed = false

    func claim() -> Bool {
        lock.withLock {
            defer { isClaimed = true }
            return !isClaimed
        }
    }
}

/// The socket itself, kept off the main actor.
nonisolated private final class Listener: @unchecked Sendable {
    var handler: (@Sendable ([String: Any], @escaping @Sendable (String) -> Void) -> Void)?

    private let lock = NSLock()
    private var serverFD: Int32 = -1
    private var connectionCount = 0

    private static let maxPayload = 1_048_576
    private static let maxConnections = 32
    private static let receiveTimeoutSeconds = 5

    var isRunning: Bool {
        lock.withLock { serverFD >= 0 }
    }

    func start(path: String) {
        let directory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        chmod(directory, 0o700)

        var address = sockaddr_un()
        let maxPathBytes = MemoryLayout.size(ofValue: address.sun_path) - 1
        guard path.utf8.count <= maxPathBytes else { return }

        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }

        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            for (index, byte) in path.utf8.enumerated() {
                raw[index] = byte
            }
        }

        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 32) == 0 else {
            close(fd)
            return
        }

        lock.withLock { serverFD = fd }
        Thread.detachNewThread { [self] in
            acceptLoop(fd: fd)
        }
    }

    func stop() {
        let fd = lock.withLock { () -> Int32 in
            let fd = serverFD
            serverFD = -1
            return fd
        }
        guard fd >= 0 else { return }
        // Closing wakes `accept` with an error, which ends the loop.
        shutdown(fd, SHUT_RDWR)
        close(fd)
        unlink(AgentHookPaths.socket.path)
    }

    private func acceptLoop(fd: Int32) {
        while true {
            let client = accept(fd, nil, nil)
            guard client >= 0 else {
                if errno == EINTR { continue }
                return
            }

            var uid: uid_t = 0
            var gid: gid_t = 0
            guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else {
                close(client)
                continue
            }

            let accepted = lock.withLock { () -> Bool in
                guard connectionCount < Self.maxConnections else { return false }
                connectionCount += 1
                return true
            }
            guard accepted else {
                close(client)
                continue
            }

            Thread.detachNewThread { [self] in
                serve(client)
            }
        }
    }

    private func serve(_ fd: Int32) {
        var timeout = timeval(tv_sec: Self.receiveTimeoutSeconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        let line = readLine(fd)
        guard let line,
              let payload = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let handler else {
            finish(fd)
            return
        }

        let once = ReplyOnce()
        handler(payload) { [self] text in
            guard once.claim() else { return }
            send(text + "\n", to: fd)
            finish(fd)
        }
    }

    private func readLine(_ fd: Int32) -> Data? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)

        while data.count <= Self.maxPayload {
            let count = recv(fd, &buffer, buffer.count, 0)
            guard count > 0 else { break }
            if let newline = buffer[0..<count].firstIndex(of: UInt8(ascii: "\n")) {
                data.append(contentsOf: buffer[0..<newline])
                return data
            }
            data.append(contentsOf: buffer[0..<count])
        }

        return data.isEmpty || data.count > Self.maxPayload ? nil : data
    }

    private func send(_ text: String, to fd: Int32) {
        let bytes = Array(text.utf8)
        var sent = 0
        while sent < bytes.count {
            let count = bytes[sent...].withUnsafeBytes { Darwin.send(fd, $0.baseAddress, $0.count, 0) }
            guard count > 0 else { return }
            sent += count
        }
    }

    private func finish(_ fd: Int32) {
        close(fd)
        lock.withLock { connectionCount -= 1 }
    }
}
