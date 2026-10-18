import Foundation

/// A computer on the local network the island can wake with Wake-on-LAN,
/// and optionally check for being online (`host`: an IP or a `.local` name).
nonisolated struct WakeComputer: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var mac: String
    var host: String

    init(id: UUID = UUID(), name: String = "", mac: String = "", host: String = "") {
        self.id = id
        self.name = name
        self.mac = mac
        self.host = host
    }

    /// The name, or "Computer" when it's left empty.
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AppLocalization.string("island.computers.unnamed") : trimmed
    }

    var macBytes: [UInt8]? {
        WakeOnLAN.macBytes(mac)
    }

    var trimmedHost: String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Storage

    /// The defaults key (`DynamicIslandSettings.Keys.wakeComputers`).
    static let storageKey = "dynamicIsland.wakeComputers"

    /// Stored as a property-list dictionary per computer.
    init?(plist: [String: String]) {
        guard let rawID = plist["id"], let id = UUID(uuidString: rawID) else { return nil }
        self.init(id: id, name: plist["name"] ?? "", mac: plist["mac"] ?? "", host: plist["host"] ?? "")
    }

    var plist: [String: String] {
        ["id": id.uuidString, "name": name, "mac": mac, "host": host]
    }

    static func load(from defaults: UserDefaults = .standard) -> [WakeComputer] {
        let raw = defaults.array(forKey: storageKey) as? [[String: String]] ?? []
        return raw.compactMap(WakeComputer.init(plist:))
    }

    static func save(_ computers: [WakeComputer], to defaults: UserDefaults = .standard) {
        defaults.set(computers.map(\.plist), forKey: storageKey)
    }
}

/// What the island knows about a computer right now.
nonisolated enum WakeComputerStatus: Equatable, Sendable {
    /// No address to check, or not checked yet.
    case unknown
    case online
    case offline
    /// Its address is on a home network this Mac isn't on right now, so
    /// whether it's on can't be known (and a wake packet wouldn't reach it).
    case away
    /// Its address belongs to this Mac (e.g. the router gave the computer's
    /// old address to the Mac), so it can't be checked.
    case thisMacAddress
    /// A magic packet went out; waiting for the computer to answer.
    case waking(since: Date)

    var isOnline: Bool { self == .online }
}

/// Wake-on-LAN magic packets. Pure, unit-tested.
nonisolated enum WakeOnLAN {
    /// The UDP port wake packets are broadcast to.
    static let port: UInt16 = 9
    /// How long a woken computer may take to come online before it's shown
    /// as offline again.
    static let wakeTimeout: TimeInterval = 120

    /// "AA:BB:CC:DD:EE:FF", "aa-bb-cc-dd-ee-ff", "aabb.ccdd.eeff" or
    /// "AABBCCDDEEFF" → 6 bytes; nil when it isn't a MAC address.
    static func macBytes(_ text: String) -> [UInt8]? {
        let hex = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { $0 != ":" && $0 != "-" && $0 != "." && $0 != " " }
        guard hex.count == 12, hex.allSatisfy(\.isHexDigit) else { return nil }
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return bytes
    }

    /// Six 0xFF bytes followed by the MAC address sixteen times (102 bytes).
    static func magicPacket(for mac: [UInt8]) -> [UInt8]? {
        guard mac.count == 6 else { return nil }
        return [UInt8](repeating: 0xFF, count: 6) + Array([[UInt8]](repeating: mac, count: 16).joined())
    }

    /// "AA:BB:CC:DD:EE:FF", for display.
    static func formatted(_ mac: [UInt8]) -> String {
        mac.map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}

/// An IPv4 network one of this Mac's interfaces is on.
nonisolated struct IPv4Subnet: Equatable, Sendable {
    let address: UInt32
    let mask: UInt32

    func contains(_ other: UInt32) -> Bool {
        address & mask == other & mask
    }
}

/// Whether a computer's address can be reached from the network this Mac
/// is on. Pure, unit-tested.
nonisolated enum LocalNetworkReach {
    /// "192.168.1.20" → its 32-bit value, for private (10/8, 172.16/12,
    /// 192.168/16) and link-local (169.254/16) addresses only; anything
    /// else (a public or Tailscale 100.x address, a name) is nil.
    static func privateIPv4(_ text: String) -> UInt32? {
        guard let value = ipv4(text) else { return nil }
        let first = value >> 24, second = value >> 16 & 0xFF
        let isPrivate = first == 10
            || (first == 172 && (16...31).contains(second))
            || (first == 192 && second == 168)
            || (first == 169 && second == 254)
        return isPrivate ? value : nil
    }

    /// Whether a `.local` (Bonjour) name, only resolvable on its own network.
    static func isLocalName(_ host: String) -> Bool {
        host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasSuffix(".local")
    }

    /// True when the address (a private IP, or the last address a `.local`
    /// name had) is on none of this Mac's networks. Unknown addresses and
    /// public/VPN ones are never "away".
    /// Whether `host` is one of this Mac's own addresses.
    static func isOwnAddress(_ host: String, subnets: [IPv4Subnet]) -> Bool {
        guard let address = ipv4(host) else { return false }
        return subnets.contains { $0.address == address }
    }

    /// The addresses to check a computer at: its host (unless that's this
    /// Mac's own address) and the address the ARP table has for its MAC,
    /// in case the router gave it a new one.
    static func probeHosts(host: String, arpAddress: String?, subnets: [IPv4Subnet]) -> [String] {
        var hosts: [String] = []
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, !isOwnAddress(trimmed, subnets: subnets) { hosts.append(trimmed) }
        if let arpAddress, !hosts.contains(arpAddress), !isOwnAddress(arpAddress, subnets: subnets) {
            hosts.append(arpAddress)
        }
        return hosts
    }

    /// Any dotted IPv4 address → its 32-bit value.
    static func ipv4(_ text: String) -> UInt32? {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var value: UInt32 = 0
        for part in parts {
            guard !part.isEmpty, part.count <= 3, part.allSatisfy(\.isASCII), let octet = UInt32(part), octet <= 255 else { return nil }
            value = value << 8 | octet
        }
        return value
    }

    /// `arp -an` lines ("? (192.168.1.7) at a:b:c:d:e:f on en0 …") → the
    /// address of each MAC that has one. Incomplete entries are skipped.
    static func arpAddresses(_ output: String) -> [[UInt8]: String] {
        var table: [[UInt8]: String] = [:]
        for line in output.split(separator: "\n") {
            let words = line.split(separator: " ")
            guard let at = words.firstIndex(of: "at"), at > 0, at + 1 < words.count else { continue }
            let address = words[at - 1].trimmingCharacters(in: CharacterSet(charactersIn: "()"))
            let octets = words[at + 1].split(separator: ":")
            guard ipv4(address) != nil, octets.count == 6, octets.allSatisfy({ (1...2).contains($0.count) }) else { continue }
            let padded = octets.map { $0.count == 1 ? "0" + $0 : String($0) }.joined()
            if let mac = WakeOnLAN.macBytes(padded) { table[mac] = address }
        }
        return table
    }

    static func isAway(host: String, lastKnownAddress: String?, subnets: [IPv4Subnet]) -> Bool {
        guard let address = privateIPv4(host) ?? lastKnownAddress.flatMap(privateIPv4) else { return false }
        return !subnets.contains { $0.contains(address) }
    }
}
