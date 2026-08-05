import Foundation

enum ToolboxMenuLayout: String, CaseIterable, Identifiable {
    case expanded
    case grouped

    var id: String { rawValue }

    var title: String {
        switch self {
        case .expanded: AppLocalization.string("Expanded")
        case .grouped: AppLocalization.string("Grouped")
        }
    }

    var description: String {
        switch self {
        case .expanded: AppLocalization.string("Show tools directly in the menu.")
        case .grouped: AppLocalization.string("Show module menus with nested actions.")
        }
    }
}

enum ToolboxToolID: String, CaseIterable, Identifiable {
    case captureSelectedArea
    case captureOCR
    case copyFinderPath
    case imageSearch
    case dropShelf

    var id: String { rawValue }

    var title: String {
        switch self {
        case .captureSelectedArea: AppLocalization.string("Capture Selected Area")
        case .captureOCR: AppLocalization.string("Capture OCR")
        case .copyFinderPath: AppLocalization.string("Copy Finder Path")
        case .imageSearch: AppLocalization.string("Search Images")
        case .dropShelf: AppLocalization.string("Drop Shelf")
        }
    }

    var subtitle: String {
        switch self {
        case .captureSelectedArea:
            AppLocalization.string("Capture a selected screen region into the floating shelf.")
        case .captureOCR:
            AppLocalization.string("Capture a selected region and copy recognized text.")
        case .copyFinderPath:
            AppLocalization.string("Copy the front Finder window path to the clipboard.")
        case .imageSearch:
            AppLocalization.string("Search local images by filename and recognized text.")
        case .dropShelf:
            AppLocalization.string("Collect dragged files, folders, links, text, and images before sending them together.")
        }
    }

    var systemImage: String {
        switch self {
        case .captureSelectedArea: "camera.viewfinder"
        case .captureOCR: "text.viewfinder"
        case .copyFinderPath: "folder"
        case .imageSearch: "magnifyingglass"
        case .dropShelf: "tray.and.arrow.down"
        }
    }

    var categoryTitle: String {
        switch self {
        case .captureSelectedArea, .captureOCR, .imageSearch:
            AppLocalization.string("Screenshots")
        case .copyFinderPath, .dropShelf:
            AppLocalization.string("Files")
        }
    }

    var enabledKey: String {
        switch self {
        case .captureSelectedArea: ToolboxSettings.Keys.captureSelectedAreaEnabled
        case .captureOCR: ToolboxSettings.Keys.captureOCREnabled
        case .copyFinderPath: ToolboxSettings.Keys.copyFinderPathEnabled
        case .imageSearch: ToolboxSettings.Keys.imageSearchEnabled
        case .dropShelf: ToolboxSettings.Keys.dropShelfEnabled
        }
    }

    var showInMenuKey: String {
        switch self {
        case .captureSelectedArea: ToolboxSettings.Keys.captureSelectedAreaShowInMenu
        case .captureOCR: ToolboxSettings.Keys.captureOCRShowInMenu
        case .copyFinderPath: ToolboxSettings.Keys.copyFinderPathShowInMenu
        case .imageSearch: ToolboxSettings.Keys.imageSearchShowInMenu
        case .dropShelf: ToolboxSettings.Keys.dropShelfShowInMenu
        }
    }

    var defaultEnabled: Bool {
        switch self {
        case .captureSelectedArea: ToolboxSettings.defaultCaptureSelectedAreaEnabled
        case .captureOCR: ToolboxSettings.defaultCaptureOCREnabled
        case .copyFinderPath: ToolboxSettings.defaultCopyFinderPathEnabled
        case .imageSearch: ToolboxSettings.defaultImageSearchEnabled
        case .dropShelf: ToolboxSettings.defaultDropShelfEnabled
        }
    }

    var defaultShowInMenu: Bool {
        switch self {
        case .captureSelectedArea: ToolboxSettings.defaultCaptureSelectedAreaShowInMenu
        case .captureOCR: ToolboxSettings.defaultCaptureOCRShowInMenu
        case .copyFinderPath: ToolboxSettings.defaultCopyFinderPathShowInMenu
        case .imageSearch: ToolboxSettings.defaultImageSearchShowInMenu
        case .dropShelf: ToolboxSettings.defaultDropShelfShowInMenu
        }
    }
}

enum ToolboxSettings {
    enum Keys {
        static let menuLayout = "toolbox.menuLayout"
        static let language = "app.language"
        static let captureSelectedAreaEnabled = "tool.captureSelectedArea.enabled"
        static let captureSelectedAreaShowInMenu = "tool.captureSelectedArea.showInMenu"
        static let captureOCREnabled = "tool.captureOCR.enabled"
        static let captureOCRShowInMenu = "tool.captureOCR.showInMenu"
        static let copyFinderPathEnabled = "tool.copyFinderPath.enabled"
        static let copyFinderPathShowInMenu = "tool.copyFinderPath.showInMenu"
        static let imageSearchEnabled = "tool.imageSearch.enabled"
        static let imageSearchShowInMenu = "tool.imageSearch.showInMenu"
        static let dropShelfEnabled = "tool.dropShelf.enabled"
        static let dropShelfShowInMenu = "tool.dropShelf.showInMenu"
    }

    static let defaultMenuLayout = ToolboxMenuLayout.expanded
    static let defaultLanguage = AppLanguage.english
    static let defaultCaptureSelectedAreaEnabled = true
    static let defaultCaptureSelectedAreaShowInMenu = true
    static let defaultCaptureOCREnabled = true
    static let defaultCaptureOCRShowInMenu = true
    static let defaultCopyFinderPathEnabled = true
    static let defaultCopyFinderPathShowInMenu = true
    static let defaultImageSearchEnabled = true
    static let defaultImageSearchShowInMenu = true
    static let defaultDropShelfEnabled = true
    static let defaultDropShelfShowInMenu = true

    static func registerDefaults(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: defaultValues)
    }

    static func resetTools(_ tools: [ToolboxToolID], in defaults: UserDefaults = .standard) {
        for tool in tools {
            defaults.set(tool.defaultEnabled, forKey: tool.enabledKey)
            defaults.set(tool.defaultEnabled && tool.defaultShowInMenu, forKey: tool.showInMenuKey)
        }
    }

    private static var defaultValues: [String: Any] {
        [
            Keys.menuLayout: defaultMenuLayout.rawValue,
            Keys.language: defaultLanguage.rawValue,
            Keys.captureSelectedAreaEnabled: defaultCaptureSelectedAreaEnabled,
            Keys.captureSelectedAreaShowInMenu: defaultCaptureSelectedAreaShowInMenu,
            Keys.captureOCREnabled: defaultCaptureOCREnabled,
            Keys.captureOCRShowInMenu: defaultCaptureOCRShowInMenu,
            Keys.copyFinderPathEnabled: defaultCopyFinderPathEnabled,
            Keys.copyFinderPathShowInMenu: defaultCopyFinderPathShowInMenu,
            Keys.imageSearchEnabled: defaultImageSearchEnabled,
            Keys.imageSearchShowInMenu: defaultImageSearchShowInMenu,
            Keys.dropShelfEnabled: defaultDropShelfEnabled,
            Keys.dropShelfShowInMenu: defaultDropShelfShowInMenu
        ]
    }

    static func isEnabled(_ tool: ToolboxToolID, defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: tool.enabledKey)
    }
}
