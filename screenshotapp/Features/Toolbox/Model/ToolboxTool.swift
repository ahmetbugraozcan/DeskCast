import Foundation

enum ToolboxMenuLayout: String, CaseIterable, Identifiable {
    /// Popover with tool tiles, the playing track and recent captures.
    case panel
    case expanded
    case grouped

    var id: String { rawValue }
}

enum ToolCategory {
    case screenshots
    case files
    case media

    /// Localization key (not the resolved string) so the model stays language-agnostic.
    var titleKey: String {
        switch self {
        case .screenshots: "Screenshots"
        case .files: "Files"
        case .media: "Media"
        }
    }
}

/// Stable identifier for a tool. Metadata lives in `ToolboxCatalog`, so adding a
/// tool means adding one row there instead of editing parallel switches.
enum ToolboxToolID: String, CaseIterable, Identifiable {
    case captureSelectedArea
    case captureVideo
    case captureOCR
    case pickColor
    case copyFinderPath
    case imageSearch
    case dropShelf
    case dynamicIsland

    var id: String { rawValue }

    var descriptor: ToolboxTool { ToolboxCatalog.tool(for: self) }

    var systemImage: String { descriptor.systemImage }
    var defaultEnabled: Bool { descriptor.defaultEnabled }
    var defaultShowInMenu: Bool { descriptor.defaultShowInMenu }

    // Keys are derived from the raw value so they cannot drift from the catalog.
    var enabledKey: String { "tool.\(rawValue).enabled" }
    var showInMenuKey: String { "tool.\(rawValue).showInMenu" }
}

/// One descriptor per tool; the single source of truth for tool metadata/defaults.
struct ToolboxTool {
    let id: ToolboxToolID
    let titleKey: String
    let subtitleKey: String
    let systemImage: String
    let category: ToolCategory
    let defaultEnabled: Bool
    let defaultShowInMenu: Bool
}

enum ToolboxCatalog {
    static let all: [ToolboxTool] = [
        ToolboxTool(
            id: .captureSelectedArea,
            titleKey: "Capture Selected Area",
            subtitleKey: "Capture a selected screen region into the floating shelf.",
            systemImage: "camera.viewfinder",
            category: .screenshots,
            defaultEnabled: true,
            defaultShowInMenu: true
        ),
        ToolboxTool(
            id: .captureVideo,
            titleKey: "Capture Video",
            subtitleKey: "Record a full display or a resizable selected area with audio options.",
            systemImage: "record.circle",
            category: .screenshots,
            defaultEnabled: true,
            defaultShowInMenu: true
        ),
        ToolboxTool(
            id: .captureOCR,
            titleKey: "Capture OCR",
            subtitleKey: "Capture a selected region and copy recognized text or QR code contents.",
            systemImage: "text.viewfinder",
            category: .screenshots,
            defaultEnabled: true,
            defaultShowInMenu: true
        ),
        ToolboxTool(
            id: .pickColor,
            titleKey: "Pick Color",
            subtitleKey: "Pick a color anywhere on screen and copy it as HEX, RGB, HSL or SwiftUI.",
            systemImage: "eyedropper.halffull",
            category: .screenshots,
            defaultEnabled: true,
            defaultShowInMenu: true
        ),
        ToolboxTool(
            id: .copyFinderPath,
            titleKey: "Copy Finder Path",
            subtitleKey: "Copy the front Finder window path to the clipboard.",
            systemImage: "folder",
            category: .files,
            defaultEnabled: true,
            defaultShowInMenu: true
        ),
        ToolboxTool(
            id: .imageSearch,
            titleKey: "Search Images",
            subtitleKey: "Search local images by filename and recognized text.",
            systemImage: "magnifyingglass",
            category: .screenshots,
            defaultEnabled: true,
            defaultShowInMenu: true
        ),
        ToolboxTool(
            id: .dropShelf,
            titleKey: "Drop Shelf",
            subtitleKey: "Collect dragged files, folders, links, text, and images before sending them together.",
            systemImage: "tray.and.arrow.down",
            category: .files,
            defaultEnabled: true,
            defaultShowInMenu: true
        ),
        ToolboxTool(
            id: .dynamicIsland,
            titleKey: "Dynamic Island",
            subtitleKey: "Show the playing song, media controls, and notifications around the notch.",
            systemImage: "capsule.fill",
            category: .media,
            defaultEnabled: true,
            defaultShowInMenu: true
        )
    ]

    static func tool(for id: ToolboxToolID) -> ToolboxTool {
        all.first { $0.id == id } ?? all[0]
    }
}

enum ToolboxSettings {
    enum Keys {
        static let menuLayout = "toolbox.menuLayout"
        /// One-time switch of existing installs to the panel menu (not a setting).
        static let menuPanelMigrated = "toolbox.menuPanelMigrated"
        static let language = "app.language"
        static let captureSelectedAreaEnabled = ToolboxToolID.captureSelectedArea.enabledKey
        static let captureSelectedAreaShowInMenu = ToolboxToolID.captureSelectedArea.showInMenuKey
        static let captureVideoEnabled = ToolboxToolID.captureVideo.enabledKey
        static let captureVideoShowInMenu = ToolboxToolID.captureVideo.showInMenuKey
        static let captureOCREnabled = ToolboxToolID.captureOCR.enabledKey
        static let captureOCRShowInMenu = ToolboxToolID.captureOCR.showInMenuKey
        static let pickColorEnabled = ToolboxToolID.pickColor.enabledKey
        static let pickColorShowInMenu = ToolboxToolID.pickColor.showInMenuKey
        static let copyFinderPathEnabled = ToolboxToolID.copyFinderPath.enabledKey
        static let copyFinderPathShowInMenu = ToolboxToolID.copyFinderPath.showInMenuKey
        static let imageSearchEnabled = ToolboxToolID.imageSearch.enabledKey
        static let imageSearchShowInMenu = ToolboxToolID.imageSearch.showInMenuKey
        static let dropShelfEnabled = ToolboxToolID.dropShelf.enabledKey
        static let dropShelfShowInMenu = ToolboxToolID.dropShelf.showInMenuKey
        static let dynamicIslandEnabled = ToolboxToolID.dynamicIsland.enabledKey
        static let dynamicIslandShowInMenu = ToolboxToolID.dynamicIsland.showInMenuKey
    }

    static let defaultMenuLayout = ToolboxMenuLayout.panel
    static let defaultLanguage = AppLanguage.english
    static let defaultCaptureSelectedAreaEnabled = ToolboxToolID.captureSelectedArea.defaultEnabled
    static let defaultCaptureSelectedAreaShowInMenu = ToolboxToolID.captureSelectedArea.defaultShowInMenu
    static let defaultCaptureVideoEnabled = ToolboxToolID.captureVideo.defaultEnabled
    static let defaultCaptureVideoShowInMenu = ToolboxToolID.captureVideo.defaultShowInMenu
    static let defaultCaptureOCREnabled = ToolboxToolID.captureOCR.defaultEnabled
    static let defaultCaptureOCRShowInMenu = ToolboxToolID.captureOCR.defaultShowInMenu
    static let defaultPickColorEnabled = ToolboxToolID.pickColor.defaultEnabled
    static let defaultPickColorShowInMenu = ToolboxToolID.pickColor.defaultShowInMenu
    static let defaultCopyFinderPathEnabled = ToolboxToolID.copyFinderPath.defaultEnabled
    static let defaultCopyFinderPathShowInMenu = ToolboxToolID.copyFinderPath.defaultShowInMenu
    static let defaultImageSearchEnabled = ToolboxToolID.imageSearch.defaultEnabled
    static let defaultImageSearchShowInMenu = ToolboxToolID.imageSearch.defaultShowInMenu
    static let defaultDropShelfEnabled = ToolboxToolID.dropShelf.defaultEnabled
    static let defaultDropShelfShowInMenu = ToolboxToolID.dropShelf.defaultShowInMenu
    static let defaultDynamicIslandEnabled = ToolboxToolID.dynamicIsland.defaultEnabled
    static let defaultDynamicIslandShowInMenu = ToolboxToolID.dynamicIsland.defaultShowInMenu

    static func registerDefaults(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: defaultValues)
        migrateToPanelMenu(in: defaults)
    }

    /// The panel replaced the plain menu as the default; move existing
    /// installs over once, after which a picked layout sticks.
    static func migrateToPanelMenu(in defaults: UserDefaults) {
        guard !defaults.bool(forKey: Keys.menuPanelMigrated) else { return }
        defaults.set(true, forKey: Keys.menuPanelMigrated)
        defaults.removeObject(forKey: Keys.menuLayout)
    }

    static func resetTools(_ tools: [ToolboxToolID], in defaults: UserDefaults = .standard) {
        for tool in tools {
            defaults.set(tool.defaultEnabled, forKey: tool.enabledKey)
            defaults.set(tool.defaultEnabled && tool.defaultShowInMenu, forKey: tool.showInMenuKey)
        }
    }

    private static var defaultValues: [String: Any] {
        var values: [String: Any] = [
            Keys.menuLayout: defaultMenuLayout.rawValue,
            Keys.language: defaultLanguage.rawValue
        ]

        for tool in ToolboxToolID.allCases {
            values[tool.enabledKey] = tool.defaultEnabled
            values[tool.showInMenuKey] = tool.defaultShowInMenu
        }

        return values
    }

    static func isEnabled(_ tool: ToolboxToolID, defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: tool.enabledKey)
    }
}
