import Foundation

/// What a round side button of the expanded island opens.
enum IslandOrbItem: Hashable {
    case launcher
    case settings
    case panel(IslandPanel)

    /// Stored as "launcher", "settings" or "panel.<panel>".
    init?(rawValue: String) {
        switch rawValue {
        case "launcher": self = .launcher
        case "settings": self = .settings
        default:
            guard rawValue.hasPrefix("panel."),
                  let panel = IslandPanel(rawValue: String(rawValue.dropFirst("panel.".count))) else { return nil }
            self = .panel(panel)
        }
    }

    var rawValue: String {
        switch self {
        case .launcher: "launcher"
        case .settings: "settings"
        case .panel(let panel): "panel.\(panel.rawValue)"
        }
    }

    var systemImage: String {
        switch self {
        case .launcher: "square.grid.2x2"
        case .settings: "gearshape"
        case .panel(let panel): panel.systemImage
        }
    }

    var titleKey: String {
        switch self {
        case .launcher: "island.orb.launcher"
        case .settings: "island.orb.settings"
        case .panel(let panel): panel.titleKey
        }
    }

    static var all: [IslandOrbItem] {
        [.launcher, .settings] + IslandPanel.allCases.map(IslandOrbItem.panel)
    }
}

/// Where side buttons sit: a column left and right of the island, and a
/// row under it.
enum IslandOrbSide: String, CaseIterable {
    case left
    case right
    case bottom

    var titleKey: String { "island.orb.side.\(rawValue)" }
}

/// The user's side buttons. Each item appears at most once, and each side
/// holds at most `maxPerSide`.
struct IslandOrbLayout: Equatable {
    var left: [IslandOrbItem]
    var right: [IslandOrbItem]
    var bottom: [IslandOrbItem]

    static let maxPerSide = 4

    static let standard = IslandOrbLayout(
        left: [.launcher, .panel(.timer)],
        right: [.settings, .panel(.volume)],
        bottom: [.panel(.nowPlaying)]
    )

    subscript(side: IslandOrbSide) -> [IslandOrbItem] {
        get {
            switch side {
            case .left: left
            case .right: right
            case .bottom: bottom
            }
        }
        set {
            switch side {
            case .left: left = newValue
            case .right: right = newValue
            case .bottom: bottom = newValue
            }
        }
    }

    var allItems: [IslandOrbItem] {
        left + right + bottom
    }

    /// Items not placed anywhere yet.
    var unusedItems: [IslandOrbItem] {
        IslandOrbItem.all.filter { !allItems.contains($0) }
    }

    func canAdd(to side: IslandOrbSide) -> Bool {
        self[side].count < Self.maxPerSide && !unusedItems.isEmpty
    }

    mutating func add(_ item: IslandOrbItem, to side: IslandOrbSide) {
        remove(item)
        guard self[side].count < Self.maxPerSide else { return }
        self[side].append(item)
    }

    mutating func remove(_ item: IslandOrbItem) {
        for side in IslandOrbSide.allCases {
            self[side].removeAll { $0 == item }
        }
    }

    /// Moves an item one place up (-1) or down (+1) within its side.
    mutating func move(_ item: IslandOrbItem, by offset: Int) {
        for side in IslandOrbSide.allCases {
            guard let index = self[side].firstIndex(of: item) else { continue }
            let target = index + offset
            guard self[side].indices.contains(target) else { return }
            self[side].swapAt(index, target)
            return
        }
    }

    /// From stored raw values: unknown and repeated items are dropped, sides capped.
    init(left: [String], right: [String], bottom: [String]) {
        var seen = Set<IslandOrbItem>()
        func parse(_ raw: [String]) -> [IslandOrbItem] {
            var items: [IslandOrbItem] = []
            for value in raw {
                guard let item = IslandOrbItem(rawValue: value), !seen.contains(item), items.count < Self.maxPerSide else { continue }
                seen.insert(item)
                items.append(item)
            }
            return items
        }
        self.left = parse(left)
        self.right = parse(right)
        self.bottom = parse(bottom)
    }

    init(left: [IslandOrbItem], right: [IslandOrbItem], bottom: [IslandOrbItem]) {
        self.left = left
        self.right = right
        self.bottom = bottom
    }

    func rawValues(for side: IslandOrbSide) -> [String] {
        self[side].map(\.rawValue)
    }
}
