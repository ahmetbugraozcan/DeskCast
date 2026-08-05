import CoreGraphics
import Foundation

enum PreviewPosition: String, CaseIterable, Identifiable {
    case bottomLeft = "bottom-left"
    case bottomRight = "bottom-right"
    case topLeft = "top-left"
    case topRight = "top-right"

    var id: String { rawValue }
}

enum StackDirection: String, CaseIterable, Identifiable {
    case horizontal
    case vertical

    var id: String { rawValue }
}

enum ShelfThumbnailSize: String, CaseIterable, Identifiable {
    case small
    case medium
    case large
    case custom

    var id: String { rawValue }

    var referenceWidth: CGFloat {
        switch self {
        case .small: 132
        case .medium: 176
        case .large: 240
        case .custom: 176
        }
    }

    func size(customWidth: Int, aspectRatio: CGFloat) -> CGSize {
        switch self {
        case .custom: Self.size(forWidth: CGFloat(customWidth), aspectRatio: aspectRatio)
        default: Self.size(forWidth: referenceWidth, aspectRatio: aspectRatio)
        }
    }

    static func size(forWidth width: CGFloat, aspectRatio: CGFloat) -> CGSize {
        let ratio = max(aspectRatio, 0.2)
        return CGSize(width: width, height: (width / ratio).rounded())
    }
}

/// Width-to-height ratio of a floating screenshot thumbnail so it can be shaped
/// like the rectangular previews macOS uses instead of a fixed near-square.
enum ShelfThumbnailAspectRatio: String, CaseIterable, Identifiable {
    case ratio16x9
    case ratio16x10
    case ratio3x2
    case ratio4x3
    case square
    case custom

    var id: String { rawValue }

    /// width / height
    func value(customWidth: Int, customHeight: Int) -> CGFloat {
        switch self {
        case .ratio16x9: 16.0 / 9.0
        case .ratio16x10: 16.0 / 10.0
        case .ratio3x2: 3.0 / 2.0
        case .ratio4x3: 4.0 / 3.0
        case .square: 1.0
        case .custom: CGFloat(max(customWidth, 1)) / CGFloat(max(customHeight, 1))
        }
    }
}

struct ScreenshotShelfSettingsSnapshot {
    let previewPosition: PreviewPosition
    let stackDirection: StackDirection
    let maxStackCount: Int
    let previewDurationSeconds: Int
    let neverAutoHide: Bool
    let pinScreenshotsByDefault: Bool
    let showPreviewsOnFocusedDisplay: Bool
    let copyCapturedScreenshotToClipboard: Bool
    let thumbnailSize: ShelfThumbnailSize
    let customThumbnailWidth: Int
    let thumbnailAspectRatio: ShelfThumbnailAspectRatio
    let customThumbnailAspectWidth: Int
    let customThumbnailAspectHeight: Int
    let autoSaveCapturedScreenshots: Bool
    let saveDirectoryPath: String

    var aspectRatioValue: CGFloat {
        thumbnailAspectRatio.value(
            customWidth: customThumbnailAspectWidth,
            customHeight: customThumbnailAspectHeight
        )
    }

    var thumbnailDimensions: CGSize {
        thumbnailSize.size(customWidth: customThumbnailWidth, aspectRatio: aspectRatioValue)
    }

    var saveDirectoryURL: URL {
        URL(fileURLWithPath: saveDirectoryPath, isDirectory: true)
    }
}

enum ScreenshotShelfSettings {
    enum Keys {
        static let previewPosition = "previewPosition"
        static let stackDirection = "stackDirection"
        static let maxStackCount = "maxStackCount"
        static let previewDurationSeconds = "previewDurationSeconds"
        static let neverAutoHide = "neverAutoHide"
        static let pinScreenshotsByDefault = "pinScreenshotsByDefault"
        static let showPreviewsOnFocusedDisplay = "showPreviewsOnFocusedDisplay"
        static let copyCapturedScreenshotToClipboard = "copyCapturedScreenshotToClipboard"
        static let thumbnailSize = "thumbnailSize"
        static let customThumbnailWidth = "customThumbnailWidth"
        static let thumbnailAspectRatio = "thumbnailAspectRatio"
        static let customThumbnailAspectWidth = "customThumbnailAspectWidth"
        static let customThumbnailAspectHeight = "customThumbnailAspectHeight"
        static let autoSaveCapturedScreenshots = "autoSaveCapturedScreenshots"
        static let saveDirectoryPath = "saveDirectoryPath"
        static let exportFilenamePrefix = "exportFilenamePrefix"
        static let exportFilenameVariants = "exportFilenameVariants"
    }

    static let maxStackCountRange = 1...10
    static let previewDurationRange = 1...60
    static let customThumbnailWidthRange = 120...420
    static let customThumbnailAspectComponentRange = 1...32

    static let defaultPreviewPosition = PreviewPosition.bottomRight
    static let defaultStackDirection = StackDirection.horizontal
    static let defaultMaxStackCount = 5
    static let defaultPreviewDurationSeconds = 8
    static let defaultNeverAutoHide = true
    static let defaultPinScreenshotsByDefault = false
    static let defaultShowPreviewsOnFocusedDisplay = true
    static let defaultCopyCapturedScreenshotToClipboard = false
    static let defaultThumbnailSize = ShelfThumbnailSize.medium
    static let defaultCustomThumbnailWidth = 220
    static let defaultThumbnailAspectRatio = ShelfThumbnailAspectRatio.ratio16x10
    static let defaultCustomThumbnailAspectWidth = 16
    static let defaultCustomThumbnailAspectHeight = 10
    static let defaultAutoSaveCapturedScreenshots = true
    static let defaultSaveDirectoryPath = FileManager.default.urls(
        for: .desktopDirectory,
        in: .userDomainMask
    ).first?.path ?? NSHomeDirectory().appending("/Desktop")
    static let defaultExportFilenamePrefix = ScreenshotExportNaming.defaultPrefix
    static let defaultExportFilenameVariants = ScreenshotExportNaming.defaultVariants

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
            Keys.previewPosition: defaultPreviewPosition.rawValue,
            Keys.stackDirection: defaultStackDirection.rawValue,
            Keys.maxStackCount: defaultMaxStackCount,
            Keys.previewDurationSeconds: defaultPreviewDurationSeconds,
            Keys.neverAutoHide: defaultNeverAutoHide,
            Keys.pinScreenshotsByDefault: defaultPinScreenshotsByDefault,
            Keys.showPreviewsOnFocusedDisplay: defaultShowPreviewsOnFocusedDisplay,
            Keys.copyCapturedScreenshotToClipboard: defaultCopyCapturedScreenshotToClipboard,
            Keys.thumbnailSize: defaultThumbnailSize.rawValue,
            Keys.customThumbnailWidth: defaultCustomThumbnailWidth,
            Keys.thumbnailAspectRatio: defaultThumbnailAspectRatio.rawValue,
            Keys.customThumbnailAspectWidth: defaultCustomThumbnailAspectWidth,
            Keys.customThumbnailAspectHeight: defaultCustomThumbnailAspectHeight,
            Keys.autoSaveCapturedScreenshots: defaultAutoSaveCapturedScreenshots,
            Keys.saveDirectoryPath: defaultSaveDirectoryPath,
            Keys.exportFilenamePrefix: defaultExportFilenamePrefix,
            Keys.exportFilenameVariants: defaultExportFilenameVariants
        ]
    }

    static func snapshot(from defaults: UserDefaults = .standard) -> ScreenshotShelfSettingsSnapshot {
        let previewPositionRaw = defaults.string(forKey: Keys.previewPosition)
        let stackDirectionRaw = defaults.string(forKey: Keys.stackDirection)
        let thumbnailSizeRaw = defaults.string(forKey: Keys.thumbnailSize)
        let thumbnailAspectRatioRaw = defaults.string(forKey: Keys.thumbnailAspectRatio)

        return ScreenshotShelfSettingsSnapshot(
            previewPosition: PreviewPosition(rawValue: previewPositionRaw ?? "") ?? defaultPreviewPosition,
            stackDirection: StackDirection(rawValue: stackDirectionRaw ?? "") ?? defaultStackDirection,
            maxStackCount: clampedMaxStackCount(defaults.integer(forKey: Keys.maxStackCount)),
            previewDurationSeconds: clampedPreviewDuration(defaults.integer(forKey: Keys.previewDurationSeconds)),
            neverAutoHide: defaults.bool(forKey: Keys.neverAutoHide),
            pinScreenshotsByDefault: defaults.bool(forKey: Keys.pinScreenshotsByDefault),
            showPreviewsOnFocusedDisplay: defaults.bool(forKey: Keys.showPreviewsOnFocusedDisplay),
            copyCapturedScreenshotToClipboard: defaults.bool(forKey: Keys.copyCapturedScreenshotToClipboard),
            thumbnailSize: ShelfThumbnailSize(rawValue: thumbnailSizeRaw ?? "") ?? defaultThumbnailSize,
            customThumbnailWidth: clampedCustomThumbnailWidth(defaults.integer(forKey: Keys.customThumbnailWidth)),
            thumbnailAspectRatio: ShelfThumbnailAspectRatio(rawValue: thumbnailAspectRatioRaw ?? "") ?? defaultThumbnailAspectRatio,
            customThumbnailAspectWidth: clampedAspectComponent(defaults.integer(forKey: Keys.customThumbnailAspectWidth)),
            customThumbnailAspectHeight: clampedAspectComponent(defaults.integer(forKey: Keys.customThumbnailAspectHeight)),
            autoSaveCapturedScreenshots: defaults.bool(forKey: Keys.autoSaveCapturedScreenshots),
            saveDirectoryPath: saveDirectoryPath(from: defaults)
        )
    }

    static func clampedMaxStackCount(_ value: Int) -> Int {
        min(max(value, maxStackCountRange.lowerBound), maxStackCountRange.upperBound)
    }

    static func clampedPreviewDuration(_ value: Int) -> Int {
        min(max(value, previewDurationRange.lowerBound), previewDurationRange.upperBound)
    }

    static var customThumbnailWidthDoubleRange: ClosedRange<Double> {
        Double(customThumbnailWidthRange.lowerBound)...Double(customThumbnailWidthRange.upperBound)
    }

    static func clampedCustomThumbnailWidth(_ value: Int) -> Int {
        min(max(value, customThumbnailWidthRange.lowerBound), customThumbnailWidthRange.upperBound)
    }

    static func clampedAspectComponent(_ value: Int) -> Int {
        min(max(value, customThumbnailAspectComponentRange.lowerBound), customThumbnailAspectComponentRange.upperBound)
    }

    private static func saveDirectoryPath(from defaults: UserDefaults) -> String {
        let path = defaults.string(forKey: Keys.saveDirectoryPath)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return path.isEmpty ? defaultSaveDirectoryPath : path
    }
}
