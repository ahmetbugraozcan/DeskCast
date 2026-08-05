import Foundation

// Localized tool/menu display strings, resolved from the catalog's keys in the
// presentation layer so the model stays language-agnostic.

extension ToolboxMenuLayout {
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

extension ToolboxToolID {
    var title: String { AppLocalization.string(descriptor.titleKey) }
    var subtitle: String { AppLocalization.string(descriptor.subtitleKey) }
    var categoryTitle: String { AppLocalization.string(descriptor.category.titleKey) }
}
