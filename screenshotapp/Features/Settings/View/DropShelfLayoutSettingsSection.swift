import SwiftUI

/// The Drop Shelf "Layout" settings block: display mode plus the controls that
/// only apply to some modes (grid column count, item size). Split out of
/// `SettingsView` to keep that file focused.
struct DropShelfLayoutSettingsSection: View {
    @Binding var layoutModeRaw: String
    @Binding var itemSizeRaw: String
    @Binding var gridColumnCount: Int
    @Binding var customItemWidth: Int

    var body: some View {
        SettingsControlSection(title: AppLocalization.string("Layout")) {
            SettingsPickerRow(title: AppLocalization.string("Display mode")) {
                Picker(AppLocalization.string("Display mode"), selection: $layoutModeRaw) {
                    ForEach(DropShelfLayoutMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.menu)
            }

            if layoutMode == .grid {
                SettingsSectionDivider()

                SettingsControlRow(
                    title: AppLocalization.formatted("Grid columns: %ld", gridColumnCount)
                ) {
                    Stepper("", value: $gridColumnCount, in: DropShelfSettings.gridColumnCountRange)
                        .labelsHidden()
                }
            }

            if layoutMode != .list {
                SettingsSectionDivider()

                SettingsPickerRow(title: AppLocalization.string("Item size")) {
                    Picker(AppLocalization.string("Item size"), selection: $itemSizeRaw) {
                        ForEach(DropShelfItemSize.allCases) { size in
                            Text(size.title).tag(size.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                }

                if itemSize == .custom {
                    SettingsSectionDivider()

                    CustomDropShelfItemSizeControl(width: $customItemWidth, height: customItemHeight)
                }
            }
        }
    }

    private var layoutMode: DropShelfLayoutMode {
        DropShelfLayoutMode(rawValue: layoutModeRaw) ?? DropShelfSettings.defaultLayoutMode
    }

    private var itemSize: DropShelfItemSize {
        DropShelfItemSize(rawValue: itemSizeRaw) ?? DropShelfSettings.defaultItemSize
    }

    private var customItemHeight: Int {
        let width = DropShelfSettings.clampedCustomItemWidth(customItemWidth)
        return Int(DropShelfItemSize.size(forWidth: CGFloat(width)).height)
    }
}
