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
