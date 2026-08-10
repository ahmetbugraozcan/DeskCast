import CoreGraphics
import Foundation

enum DropShelfLayoutMode: String, CaseIterable, Identifiable {
    case stack
    case grid
    case list

    var id: String { rawValue }
}

enum DropShelfItemSize: String, CaseIterable, Identifiable {
    case small
    case medium
    case large
    case custom

    var id: String { rawValue }

    func size(customWidth: Int) -> CGSize {
        switch self {
        case .small: Self.size(forWidth: 148)
        case .medium: Self.size(forWidth: 188)
        case .large: Self.size(forWidth: 244)
        case .custom: Self.size(forWidth: CGFloat(customWidth))
        }
    }

    static func size(forWidth width: CGFloat) -> CGSize {
        CGSize(width: width, height: max(112, (width * 0.72).rounded()))
    }
}

struct DropShelfSettingsSnapshot {
    let stackDirection: StackDirection
    let layoutMode: DropShelfLayoutMode
    let itemSize: DropShelfItemSize
    let customItemWidth: Int
    let gridColumnCount: Int
    let maxItemCount: Int
    let openOnShake: Bool
    let shakeSensitivity: Int

    var itemDimensions: CGSize {
        itemSize.size(customWidth: customItemWidth)
    }
}

enum DropShelfSettings {
    enum Keys {
        static let stackDirection = "dropShelf.stackDirection"
        static let layoutMode = "dropShelf.layoutMode"
        static let itemSize = "dropShelf.itemSize"
        static let customItemWidth = "dropShelf.customItemWidth"
        static let gridColumnCount = "dropShelf.gridColumnCount"
        static let maxItemCount = "dropShelf.maxItemCount"
        static let openOnShake = "dropShelf.openOnShake"
        static let shakeSensitivity = "dropShelf.shakeSensitivity"
    }

    static let customItemWidthRange = 128...360
    static let gridColumnCountRange = 2...5
    static let maxItemCountRange = 1...50
    static let shakeSensitivityRange = 1...10

    static let defaultStackDirection = StackDirection.horizontal
    static let defaultLayoutMode = DropShelfLayoutMode.stack
    static let defaultItemSize = DropShelfItemSize.medium
    static let defaultCustomItemWidth = 220
    static let defaultGridColumnCount = 3
    static let defaultMaxItemCount = 25
    static let defaultOpenOnShake = true
    static let defaultShakeSensitivity = 6

    static func registerDefaults(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: defaultValues)
    }

    static func resetToDefaults(in defaults: UserDefaults = .standard) {
        for (key, value) in defaultValues {
            defaults.set(value, forKey: key)
        }
    }

    private static var defaultValues: [String: Any] {
        [
            Keys.stackDirection: defaultStackDirection.rawValue,
            Keys.layoutMode: defaultLayoutMode.rawValue,
            Keys.itemSize: defaultItemSize.rawValue,
            Keys.customItemWidth: defaultCustomItemWidth,
            Keys.gridColumnCount: defaultGridColumnCount,
            Keys.maxItemCount: defaultMaxItemCount,
            Keys.openOnShake: defaultOpenOnShake,
            Keys.shakeSensitivity: defaultShakeSensitivity
        ]
    }

    static func snapshot(from defaults: UserDefaults = .standard) -> DropShelfSettingsSnapshot {
        let stackDirectionRaw = defaults.string(forKey: Keys.stackDirection)
        let layoutModeRaw = defaults.string(forKey: Keys.layoutMode)
        let itemSizeRaw = defaults.string(forKey: Keys.itemSize)

        return DropShelfSettingsSnapshot(
            stackDirection: StackDirection(rawValue: stackDirectionRaw ?? "") ?? defaultStackDirection,
            layoutMode: DropShelfLayoutMode(rawValue: layoutModeRaw ?? "") ?? defaultLayoutMode,
            itemSize: DropShelfItemSize(rawValue: itemSizeRaw ?? "") ?? defaultItemSize,
            customItemWidth: clampedCustomItemWidth(defaults.integer(forKey: Keys.customItemWidth)),
            gridColumnCount: clampedGridColumnCount(defaults.integer(forKey: Keys.gridColumnCount)),
            maxItemCount: clampedMaxItemCount(defaults.integer(forKey: Keys.maxItemCount)),
            openOnShake: defaults.bool(forKey: Keys.openOnShake),
            shakeSensitivity: clampedShakeSensitivity(defaults.integer(forKey: Keys.shakeSensitivity))
        )
    }

    static var customItemWidthDoubleRange: ClosedRange<Double> {
        Double(customItemWidthRange.lowerBound)...Double(customItemWidthRange.upperBound)
    }

    static var shakeSensitivityDoubleRange: ClosedRange<Double> {
        Double(shakeSensitivityRange.lowerBound)...Double(shakeSensitivityRange.upperBound)
    }

    static func clampedCustomItemWidth(_ value: Int) -> Int {
        min(max(value, customItemWidthRange.lowerBound), customItemWidthRange.upperBound)
    }

    static func clampedGridColumnCount(_ value: Int) -> Int {
        min(max(value, gridColumnCountRange.lowerBound), gridColumnCountRange.upperBound)
    }

    static func clampedMaxItemCount(_ value: Int) -> Int {
        min(max(value, maxItemCountRange.lowerBound), maxItemCountRange.upperBound)
    }

    static func clampedShakeSensitivity(_ value: Int) -> Int {
        min(max(value, shakeSensitivityRange.lowerBound), shakeSensitivityRange.upperBound)
    }
}
