import Darwin
import Foundation
import Network

protocol WakeOnLANSending: Sendable {
    /// Broadcasts a magic packet for `mac` on every local network. False
    /// when nothing could be sent (e.g. Local Network access was denied).
    func wake(mac: [UInt8]) async -> Bool
}

protocol HostProbing: Sendable {
    /// Whether `host` answers on the local network.
    func isOnline(host: String) async -> Bool
}

/// Sends magic packets over UDP broadcast: to 255.255.255.255 and to each
/// IPv4 interface's broadcast address, since macOS sends the former only on
/// the primary interface.
struct WakeOnLANService: WakeOnLANSending {
    func wake(mac: [UInt8]) async -> Bool {
        guard let packet = WakeOnLAN.magicPacket(for: mac) else { return false }
        return await Task.detached {
            let addresses = Set(["255.255.255.255"] + Self.interfaceBroadcastAddresses())
            let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
            guard fd >= 0 else { return false }
            defer { close(fd) }

            var on: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &on, socklen_t(MemoryLayout<Int32>.size))

            var sentAny = false
            for address in addresses {
                var target = sockaddr_in()
                target.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                target.sin_family = sa_family_t(AF_INET)
                target.sin_port = WakeOnLAN.port.bigEndian
                guard inet_pton(AF_INET, address, &target.sin_addr) == 1 else { continue }
                let sent = packet.withUnsafeBytes { buffer in
                    withUnsafePointer(to: &target) { pointer in
                        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                            sendto(fd, buffer.baseAddress, buffer.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                        }
                    }
                }
                if sent == packet.count { sentAny = true }
            }
            return sentAny
        }.value
    }

    private static func interfaceBroadcastAddresses() -> [String] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }

        var addresses: [String] = []
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(entry.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_BROADCAST != 0, flags & IFF_LOOPBACK == 0,
                  let address = entry.pointee.ifa_addr, address.pointee.sa_family == sa_family_t(AF_INET),
                  let broadcast = entry.pointee.ifa_dstaddr else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(broadcast, socklen_t(broadcast.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                addresses.append(String(cString: host))
            }
        }
        return addresses
    }
}

/// Windows doesn't answer ping by default, so a computer counts as online
/// when it accepts — or actively refuses — a TCP connection on a port
/// Windows, macOS or Linux usually has (SMB, RDP, SSH, RPC, VNC).
struct HostProbeService: HostProbing {
    static let ports: [UInt16] = [445, 3389, 22, 135, 5900]
    static let timeout: TimeInterval = 1.5

    func isOnline(host: String) async -> Bool {
        guard !host.isEmpty else { return false }
        return await withTaskGroup(of: Bool.self) { group in
            for port in Self.ports {
                group.addTask { await Self.answers(host: host, port: port) }
            }
            for await answered in group where answered {
                group.cancelAll()
                return true
            }
            return false
        }
    }

    private static func answers(host: String, port: UInt16) async -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return false }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let queue = DispatchQueue(label: "DeskCast.HostProbe")
        return await withCheckedContinuation { continuation in
            let attempt = ProbeAttempt(connection: connection, continuation: continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    attempt.finish(true)
                case .waiting(let error), .failed(let error):
                    // A refused connection still means the host is up.
                    if case .posix(let code) = error, code == .ECONNREFUSED {
                        attempt.finish(true)
                    } else if case .failed = state {
                        attempt.finish(false)
                    }
                case .cancelled:
                    attempt.finish(false)
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { attempt.finish(false) }
        }
    }
}

/// One probe's result, resumed once. Only touched on the probe's queue.
private final class ProbeAttempt: @unchecked Sendable {
    private let connection: NWConnection
    private var continuation: CheckedContinuation<Bool, Never>?

    init(connection: NWConnection, continuation: CheckedContinuation<Bool, Never>) {
        self.connection = connection
        self.continuation = continuation
    }

    func finish(_ result: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        connection.cancel()
        continuation.resume(returning: result)
    }
}
