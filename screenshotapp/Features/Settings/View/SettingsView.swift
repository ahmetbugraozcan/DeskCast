import AppKit
import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @AppStorage(ScreenshotShelfSettings.Keys.previewPosition)
    private var previewPositionRaw = ScreenshotShelfSettings.defaultPreviewPosition.rawValue

    @AppStorage(ScreenshotShelfSettings.Keys.stackDirection)
    private var stackDirectionRaw = ScreenshotShelfSettings.defaultStackDirection.rawValue

    @AppStorage(ScreenshotShelfSettings.Keys.maxStackCount)
    private var maxStackCount = ScreenshotShelfSettings.defaultMaxStackCount

    @AppStorage(ScreenshotShelfSettings.Keys.previewDurationSeconds)
    private var previewDurationSeconds = ScreenshotShelfSettings.defaultPreviewDurationSeconds

    @AppStorage(ScreenshotShelfSettings.Keys.neverAutoHide)
    private var neverAutoHide = ScreenshotShelfSettings.defaultNeverAutoHide

    @AppStorage(ScreenshotShelfSettings.Keys.pinScreenshotsByDefault)
    private var pinScreenshotsByDefault = ScreenshotShelfSettings.defaultPinScreenshotsByDefault

    @AppStorage(ScreenshotShelfSettings.Keys.showPreviewsOnFocusedDisplay)
    private var showPreviewsOnFocusedDisplay = ScreenshotShelfSettings.defaultShowPreviewsOnFocusedDisplay

    @AppStorage(ScreenshotShelfSettings.Keys.copyCapturedScreenshotToClipboard)
    private var copyCapturedScreenshotToClipboard = ScreenshotShelfSettings.defaultCopyCapturedScreenshotToClipboard

    @AppStorage(ScreenshotShelfSettings.Keys.thumbnailSize)
    private var thumbnailSizeRaw = ScreenshotShelfSettings.defaultThumbnailSize.rawValue

    @AppStorage(ScreenshotShelfSettings.Keys.customThumbnailWidth)
    private var customThumbnailWidth = ScreenshotShelfSettings.defaultCustomThumbnailWidth

    @AppStorage(ScreenshotShelfSettings.Keys.thumbnailAspectRatio)
    private var thumbnailAspectRatioRaw = ScreenshotShelfSettings.defaultThumbnailAspectRatio.rawValue

    @AppStorage(ScreenshotShelfSettings.Keys.customThumbnailAspectWidth)
    private var customThumbnailAspectWidth = ScreenshotShelfSettings.defaultCustomThumbnailAspectWidth

    @AppStorage(ScreenshotShelfSettings.Keys.customThumbnailAspectHeight)
    private var customThumbnailAspectHeight = ScreenshotShelfSettings.defaultCustomThumbnailAspectHeight

    @AppStorage(ScreenshotShelfSettings.Keys.autoSaveCapturedScreenshots)
    private var autoSaveCapturedScreenshots = ScreenshotShelfSettings.defaultAutoSaveCapturedScreenshots

    @AppStorage(ScreenshotShelfSettings.Keys.saveDirectoryPath)
    private var saveDirectoryPath = ScreenshotShelfSettings.defaultSaveDirectoryPath

    @AppStorage(ScreenshotShelfSettings.Keys.exportFilenamePrefix)
    private var exportFilenamePrefix = ScreenshotShelfSettings.defaultExportFilenamePrefix

    @AppStorage(ScreenshotShelfSettings.Keys.exportFilenameVariants)
    private var exportFilenameVariants = ScreenshotShelfSettings.defaultExportFilenameVariants

    @AppStorage(ToolboxSettings.Keys.menuLayout)
    private var menuLayoutRaw = ToolboxSettings.defaultMenuLayout.rawValue
    @AppStorage(ToolboxSettings.Keys.language)
    private var languageRaw = ToolboxSettings.defaultLanguage.rawValue

    @AppStorage(DropShelfSettings.Keys.itemSize)
    private var dropShelfItemSizeRaw = DropShelfSettings.defaultItemSize.rawValue
    @AppStorage(DropShelfSettings.Keys.layoutMode)
    private var dropShelfLayoutModeRaw = DropShelfSettings.defaultLayoutMode.rawValue

    @AppStorage(DropShelfSettings.Keys.customItemWidth)
    private var dropShelfCustomItemWidth = DropShelfSettings.defaultCustomItemWidth

    @AppStorage(DropShelfSettings.Keys.maxItemCount)
    private var dropShelfMaxItemCount = DropShelfSettings.defaultMaxItemCount

    @AppStorage(DropShelfSettings.Keys.openOnShake)
    private var dropShelfOpenOnShake = DropShelfSettings.defaultOpenOnShake

    @AppStorage(DropShelfSettings.Keys.shakeSensitivity)
    private var dropShelfShakeSensitivity = DropShelfSettings.defaultShakeSensitivity

    @AppStorage(ToolboxSettings.Keys.dropShelfEnabled)
    private var dropShelfEnabled = ToolboxSettings.defaultDropShelfEnabled

    @State private var selectedSection: SettingsSection? = .screenshots
    @StateObject private var permissionStore = PrivacyPermissionViewModel()

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedSection) {
                Section("App") {
                    ForEach(SettingsSection.appSections) { section in
                        Label(section.title, systemImage: section.systemImage)
                            .tag(section)
                    }
                }

                Section("Features") {
                    ForEach(SettingsSection.featureSections) { section in
                        Label(section.title, systemImage: section.systemImage)
                            .tag(section)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 150, ideal: 170)
        } detail: {
            selectedPane
        }
        .frame(
            minWidth: 640,
            idealWidth: 720,
            maxWidth: .infinity,
            minHeight: 460,
            idealHeight: 560,
            maxHeight: .infinity
        )
        .onAppear(perform: clampNumericSettings)
        .onChange(of: maxStackCount) { _, newValue in
            maxStackCount = ScreenshotShelfSettings.clampedMaxStackCount(newValue)
        }
        .onChange(of: previewDurationSeconds) { _, newValue in
            previewDurationSeconds = ScreenshotShelfSettings.clampedPreviewDuration(newValue)
        }
        .onChange(of: customThumbnailWidth) { _, newValue in
            customThumbnailWidth = ScreenshotShelfSettings.clampedCustomThumbnailWidth(newValue)
        }
        .onChange(of: customThumbnailAspectWidth) { _, newValue in
            customThumbnailAspectWidth = ScreenshotShelfSettings.clampedAspectComponent(newValue)
        }
        .onChange(of: customThumbnailAspectHeight) { _, newValue in
            customThumbnailAspectHeight = ScreenshotShelfSettings.clampedAspectComponent(newValue)
        }
        .onChange(of: dropShelfCustomItemWidth) { _, newValue in
            dropShelfCustomItemWidth = DropShelfSettings.clampedCustomItemWidth(newValue)
        }
        .onChange(of: dropShelfMaxItemCount) { _, newValue in
            dropShelfMaxItemCount = DropShelfSettings.clampedMaxItemCount(newValue)
        }
        .onChange(of: dropShelfShakeSensitivity) { _, newValue in
            dropShelfShakeSensitivity = DropShelfSettings.clampedShakeSensitivity(newValue)
        }
    }

    @ViewBuilder
    private var selectedPane: some View {
        switch selectedSection ?? .screenshots {
        case .menuBar:
            menuBarPane
        case .screenshots:
            screenshotsPane
        case .dropShelf:
            dropShelfPane
        case .finderPath:
            finderPathPane
        case .shortcuts:
            shortcutsPane
        }
    }

    private var menuBarPane: some View {
        SettingsPage(title: AppLocalization.string("Menu Bar"), systemImage: "menubar.rectangle") {
            VStack(alignment: .leading, spacing: 24) {
                LanguageSection(selection: $languageRaw)
                MenuLayoutSection(selection: $menuLayoutRaw)
                LaunchAtLoginSection()
            }
        }
    }

    private var screenshotsPane: some View {
        SettingsPage(title: AppLocalization.string("Screenshots"), systemImage: "camera.viewfinder") {
            ToolCategorySection(
                title: AppLocalization.string("Tools"),
                tools: [.captureSelectedArea, .captureOCR, .imageSearch]
            )

            FeaturePermissionManagerView(
                store: permissionStore,
                permissions: [.screenRecording]
            )

            VStack(alignment: .leading, spacing: 24) {
                SettingsControlSection(title: AppLocalization.string("Preview")) {
                    SettingsPickerRow(title: AppLocalization.string("Position")) {
                        Picker(AppLocalization.string("Position"), selection: $previewPositionRaw) {
                            ForEach(PreviewPosition.allCases) { position in
                                Text(position.title).tag(position.rawValue)
                            }
                        }
                    }

                    SettingsSectionDivider()

                    SettingsPickerRow(title: AppLocalization.string("Stack direction")) {
                        Picker(AppLocalization.string("Stack direction"), selection: $stackDirectionRaw) {
                            ForEach(StackDirection.allCases) { direction in
                                Text(direction.title).tag(direction.rawValue)
                            }
                        }
                    }
                }

                SettingsControlSection(title: AppLocalization.string("Thumbnail")) {
                    SettingsPickerRow(title: AppLocalization.string("Size")) {
                        Picker(AppLocalization.string("Size"), selection: $thumbnailSizeRaw) {
                            ForEach(ShelfThumbnailSize.allCases) { size in
                                Text(size.title).tag(size.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    if selectedThumbnailSize == .custom {
                        SettingsSectionDivider()

                        CustomThumbnailSizeControl(
                            width: $customThumbnailWidth,
                            height: customThumbnailHeight
                        )
                    }

                    SettingsSectionDivider()

                    SettingsPickerRow(title: AppLocalization.string("Aspect ratio")) {
                        Picker(AppLocalization.string("Aspect ratio"), selection: $thumbnailAspectRatioRaw) {
                            ForEach(ShelfThumbnailAspectRatio.allCases) { ratio in
                                Text(ratio.title).tag(ratio.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    if selectedAspectRatio == .custom {
                        SettingsSectionDivider()

                        CustomAspectRatioControl(
                            width: $customThumbnailAspectWidth,
                            height: $customThumbnailAspectHeight
                        )
                    }
                }

                SettingsControlSection(title: AppLocalization.string("Stack")) {
                    SettingsControlRow(
                        title: AppLocalization.formatted("Max stack count: %ld", maxStackCount)
                    ) {
                        Stepper(
                            "",
                            value: $maxStackCount,
                            in: ScreenshotShelfSettings.maxStackCountRange
                        )
                        .labelsHidden()
                    }

                    SettingsSectionDivider()

                    SettingsToggleRow(
                        title: AppLocalization.string("Pin screenshots by default"),
                        isOn: $pinScreenshotsByDefault
                    )
                }

                SettingsControlSection(title: AppLocalization.string("Auto-hide")) {
                    SettingsControlRow(
                        title: AppLocalization.formatted("Preview duration: %ld sec", previewDurationSeconds)
                    ) {
                        Stepper(
                            "",
                            value: $previewDurationSeconds,
                            in: ScreenshotShelfSettings.previewDurationRange
                        )
                        .labelsHidden()
                    }
                    .disabled(neverAutoHide)

                    SettingsSectionDivider()

                    SettingsToggleRow(
                        title: AppLocalization.string("Never auto-hide"),
                        isOn: $neverAutoHide
                    )
                }

                SettingsControlSection(title: AppLocalization.string("Capture")) {
                    SettingsToggleRow(
                        title: AppLocalization.string("Show previews on focused display"),
                        isOn: $showPreviewsOnFocusedDisplay
                    )

                    SettingsSectionDivider()

                    SettingsToggleRow(
                        title: AppLocalization.string("Copy new screenshots to clipboard"),
                        isOn: $copyCapturedScreenshotToClipboard
                    )
                }

                SettingsControlSection(title: AppLocalization.string("Export")) {
                    SettingsToggleRow(
                        title: AppLocalization.string("Auto-save captured screenshots"),
                        isOn: $autoSaveCapturedScreenshots
                    )

                    SettingsSectionDivider()

                    SettingsControlRow(title: AppLocalization.string("Save to")) {
                        HStack(spacing: 8) {
                            Text(saveDirectoryPath)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: 260, alignment: .trailing)

                            Button(AppLocalization.string("Choose...")) {
                                chooseSaveDirectory()
                            }
                        }
                    }

                    SettingsSectionDivider()

                    SettingsControlRow(title: AppLocalization.string("Prefix")) {
                        TextField(AppLocalization.string("Prefix"), text: $exportFilenamePrefix)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 240)
                    }

                    SettingsSectionDivider()

                    SettingsControlRow(title: AppLocalization.string("Variants")) {
                        TextField(AppLocalization.string("Variants"), text: $exportFilenameVariants)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 240)
                    }
                }

                SettingsControlSection(title: AppLocalization.string("Generated names")) {
                    ForEach(exportOptions) { option in
                        SettingsControlRow(title: option.variant ?? AppLocalization.string("Default")) {
                            Text(option.filename)
                                .monospaced()
                                .foregroundStyle(.secondary)
                        }

                        if option.id != exportOptions.last?.id {
                            SettingsSectionDivider()
                        }
                    }
                }
            }

            FeatureResetSection {
                resetScreenshotSettings()
            }
        }
    }

    private var finderPathPane: some View {
        SettingsPage(title: AppLocalization.string("Finder Path"), systemImage: "folder") {
            ToolCategorySection(
                title: AppLocalization.string("Tool"),
                tools: [.copyFinderPath]
            )

            FeaturePermissionManagerView(
                store: permissionStore,
                permissions: [.finderAutomation]
            )

            FeatureResetSection {
                resetFinderPathSettings()
            }
        }
    }

    private var dropShelfPane: some View {
        SettingsPage(title: AppLocalization.string("Drop Shelf"), systemImage: "tray.and.arrow.down") {
            ToolCategorySection(
                title: AppLocalization.string("Tool"),
                tools: [.dropShelf]
            )

            FeaturePermissionManagerView(
                store: permissionStore,
                permissions: [.accessibility]
            )

            VStack(alignment: .leading, spacing: 24) {
                SettingsControlSection(title: AppLocalization.string("Layout")) {
                    SettingsPickerRow(title: AppLocalization.string("Display mode")) {
                        Picker(AppLocalization.string("Display mode"), selection: $dropShelfLayoutModeRaw) {
                            ForEach(DropShelfLayoutMode.allCases) { mode in
                                Text(mode.title).tag(mode.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    SettingsSectionDivider()

                    SettingsPickerRow(title: AppLocalization.string("Item size")) {
                        Picker(AppLocalization.string("Item size"), selection: $dropShelfItemSizeRaw) {
                            ForEach(DropShelfItemSize.allCases) { size in
                                Text(size.title).tag(size.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    if selectedDropShelfItemSize == .custom {
                        SettingsSectionDivider()

                        CustomDropShelfItemSizeControl(
                            width: $dropShelfCustomItemWidth,
                            height: dropShelfCustomItemHeight
                        )
                    }
                }

                SettingsControlSection(title: AppLocalization.string("Capacity")) {
                    SettingsControlRow(
                        title: AppLocalization.formatted("Max item count: %ld", dropShelfMaxItemCount)
                    ) {
                        Stepper(
                            "",
                            value: $dropShelfMaxItemCount,
                            in: DropShelfSettings.maxItemCountRange
                        )
                        .labelsHidden()
                    }
                }

                SettingsControlSection(title: AppLocalization.string("Shake")) {
                    SettingsToggleRow(
                        title: AppLocalization.string("Open shelf when shaking"),
                        isOn: $dropShelfOpenOnShake
                    )

                    SettingsSectionDivider()

                    SettingsControlRow(
                        title: AppLocalization.formatted("Sensitivity: %ld", dropShelfShakeSensitivity)
                    ) {
                        HStack(spacing: 8) {
                            Text("\(DropShelfSettings.shakeSensitivityRange.lowerBound)")
                            Slider(
                                value: dropShelfShakeSensitivityBinding,
                                in: Double(DropShelfSettings.shakeSensitivityRange.lowerBound)...Double(DropShelfSettings.shakeSensitivityRange.upperBound),
                                step: 1
                            )
                            .frame(width: 190)
                            Text("\(DropShelfSettings.shakeSensitivityRange.upperBound)")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    }
                    .disabled(!dropShelfOpenOnShake)
                }
            }
            .disabled(!dropShelfEnabled)
            .opacity(dropShelfEnabled ? 1 : 0.5)

            FeatureResetSection {
                resetDropShelfSettings()
            }
        }
    }

    private var shortcutsPane: some View {
        SettingsPage(title: AppLocalization.string("Shortcuts"), systemImage: "keyboard") {
            Form {
                Section("Screenshots") {
                    KeyboardShortcuts.Recorder(
                        AppLocalization.string("Selected area:"),
                        name: .captureSelectedArea
                    )
                }

                Section("Files") {
                    KeyboardShortcuts.Recorder(
                        AppLocalization.string("Drop shelf:"),
                        name: .openDropShelf
                    )
                    .disabled(!dropShelfEnabled)
                }
            }
        }
    }

    private var selectedThumbnailSize: ShelfThumbnailSize {
        ShelfThumbnailSize(rawValue: thumbnailSizeRaw) ?? ScreenshotShelfSettings.defaultThumbnailSize
    }

    private var selectedAspectRatio: ShelfThumbnailAspectRatio {
        ShelfThumbnailAspectRatio(rawValue: thumbnailAspectRatioRaw) ?? ScreenshotShelfSettings.defaultThumbnailAspectRatio
    }

    private var aspectRatioValue: CGFloat {
        selectedAspectRatio.value(
            customWidth: ScreenshotShelfSettings.clampedAspectComponent(customThumbnailAspectWidth),
            customHeight: ScreenshotShelfSettings.clampedAspectComponent(customThumbnailAspectHeight)
        )
    }

    private var customThumbnailHeight: Int {
        let width = ScreenshotShelfSettings.clampedCustomThumbnailWidth(customThumbnailWidth)
        return Int(ShelfThumbnailSize.size(forWidth: CGFloat(width), aspectRatio: aspectRatioValue).height)
    }

    private var selectedDropShelfItemSize: DropShelfItemSize {
        DropShelfItemSize(rawValue: dropShelfItemSizeRaw) ?? DropShelfSettings.defaultItemSize
    }

    private var dropShelfCustomItemHeight: Int {
        let width = DropShelfSettings.clampedCustomItemWidth(dropShelfCustomItemWidth)
        return Int(DropShelfItemSize.size(forWidth: CGFloat(width)).height)
    }

    private var dropShelfShakeSensitivityBinding: Binding<Double> {
        Binding {
            Double(dropShelfShakeSensitivity)
        } set: { newValue in
            dropShelfShakeSensitivity = DropShelfSettings.clampedShakeSensitivity(Int(newValue.rounded()))
        }
    }

    private var exportOptions: [ScreenshotExportOption] {
        ScreenshotExportNaming.options(
            prefix: exportFilenamePrefix,
            variants: exportFilenameVariants
        )
    }

    private func clampNumericSettings() {
        maxStackCount = ScreenshotShelfSettings.clampedMaxStackCount(maxStackCount)
        previewDurationSeconds = ScreenshotShelfSettings.clampedPreviewDuration(previewDurationSeconds)
        customThumbnailWidth = ScreenshotShelfSettings.clampedCustomThumbnailWidth(customThumbnailWidth)
        customThumbnailAspectWidth = ScreenshotShelfSettings.clampedAspectComponent(customThumbnailAspectWidth)
        customThumbnailAspectHeight = ScreenshotShelfSettings.clampedAspectComponent(customThumbnailAspectHeight)
        dropShelfCustomItemWidth = DropShelfSettings.clampedCustomItemWidth(dropShelfCustomItemWidth)
        dropShelfMaxItemCount = DropShelfSettings.clampedMaxItemCount(dropShelfMaxItemCount)
        dropShelfShakeSensitivity = DropShelfSettings.clampedShakeSensitivity(dropShelfShakeSensitivity)
    }

    private func chooseSaveDirectory() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: saveDirectoryPath, isDirectory: true)
        panel.prompt = AppLocalization.string("Choose")

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        saveDirectoryPath = url.path
    }

    private func resetScreenshotSettings() {
        ScreenshotShelfSettings.resetToDefaults()
        ToolboxSettings.resetTools([.captureSelectedArea, .captureOCR, .imageSearch])
        KeyboardShortcuts.reset(.captureSelectedArea)
    }

    private func resetFinderPathSettings() {
        ToolboxSettings.resetTools([.copyFinderPath])
    }

    private func resetDropShelfSettings() {
        DropShelfSettings.resetToDefaults()
        ToolboxSettings.resetTools([.dropShelf])
        KeyboardShortcuts.reset(.openDropShelf)
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case menuBar
    case screenshots
    case dropShelf
    case finderPath
    case shortcuts

    var id: Self { self }

    static let appSections: [Self] = [.menuBar, .shortcuts]
    static let featureSections: [Self] = [.screenshots, .dropShelf, .finderPath]

    var title: String {
        switch self {
        case .menuBar: AppLocalization.string("Menu Bar")
        case .screenshots: AppLocalization.string("Screenshots")
        case .dropShelf: AppLocalization.string("Drop Shelf")
        case .finderPath: AppLocalization.string("Finder Path")
        case .shortcuts: AppLocalization.string("Shortcuts")
        }
    }

    var systemImage: String {
        switch self {
        case .menuBar: "menubar.rectangle"
        case .screenshots: "camera.viewfinder"
        case .dropShelf: "tray.and.arrow.down"
        case .finderPath: "folder"
        case .shortcuts: "keyboard"
        }
    }
}

private struct SettingsPane<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            content
                .formStyle(.grouped)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

private struct SettingsPage<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        SettingsPane {
            VStack(alignment: .leading, spacing: 18) {
                Label(title, systemImage: systemImage)
                    .font(.title2.weight(.semibold))
                    .padding(.horizontal, 4)

                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct MenuLayoutSection: View {
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Layout")
                .font(.headline)
                .foregroundStyle(.primary)
                .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 16) {
                    Text("Menu layout")
                        .font(.system(size: 13, weight: .medium))

                    Spacer()

                    Picker("Menu layout", selection: $selection) {
                        ForEach(ToolboxMenuLayout.allCases) { layout in
                            Text(layout.title).tag(layout.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize(horizontal: true, vertical: false)
                }
                .frame(maxWidth: .infinity)

                Text(selectedLayout.description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var selectedLayout: ToolboxMenuLayout {
        ToolboxMenuLayout(rawValue: selection) ?? ToolboxSettings.defaultMenuLayout
    }
}

private struct LanguageSection: View {
    @Binding var selection: String

    var body: some View {
        SettingsControlSection(title: AppLocalization.string("Language")) {
            SettingsPickerRow(title: AppLocalization.string("App language")) {
                Picker(AppLocalization.string("App language"), selection: $selection) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language.rawValue)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }
}

private struct LaunchAtLoginSection: View {
    @State private var isOn = LaunchAtLoginService.isEnabled
    @State private var errorMessage: String?

    var body: some View {
        SettingsControlSection(title: AppLocalization.string("Startup")) {
            SettingsControlRow(title: AppLocalization.string("Launch at login")) {
                Toggle("", isOn: toggleBinding)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            if let errorMessage {
                SettingsSectionDivider()

                SettingsControlRow(title: errorMessage) {
                    EmptyView()
                }
            }
        }
        .onAppear {
            isOn = LaunchAtLoginService.isEnabled
        }
    }

    private var toggleBinding: Binding<Bool> {
        Binding {
            isOn
        } set: { newValue in
            do {
                try LaunchAtLoginService.setEnabled(newValue)
                isOn = LaunchAtLoginService.isEnabled
                errorMessage = nil
            } catch {
                // Revert the switch and tell the user; the OS can reject the change
                // (e.g. the item was disabled in System Settings → Login Items).
                isOn = LaunchAtLoginService.isEnabled
                errorMessage = AppLocalization.string("Could not update the login item. Check System Settings.")
            }
        }
    }
}

private struct ToolCategorySection: View {
    let title: String
    let tools: [ToolboxToolID]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
                .padding(.horizontal, 4)

            VStack(spacing: 10) {
                ForEach(tools) { tool in
                    ToolSettingsRow(tool: tool)
                }
            }
        }
    }
}

private struct ToolSettingsRow: View {
    let tool: ToolboxToolID
    @AppStorage private var isEnabled: Bool
    @AppStorage private var showInMenu: Bool

    init(tool: ToolboxToolID) {
        self.tool = tool
        _isEnabled = AppStorage(wrappedValue: tool.defaultEnabled, tool.enabledKey)
        _showInMenu = AppStorage(wrappedValue: tool.defaultShowInMenu, tool.showInMenuKey)
    }

    private var enabledBinding: Binding<Bool> {
        Binding {
            isEnabled
        } set: { newValue in
            isEnabled = newValue

            if !newValue {
                showInMenu = false
            }
        }
    }

    private var showInMenuBinding: Binding<Bool> {
        Binding {
            isEnabled && showInMenu
        } set: { newValue in
            showInMenu = isEnabled && newValue
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: tool.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isEnabled ? Color.accentColor : Color.secondary)
                    .frame(width: 34, height: 34)
                    .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text(tool.title)
                        .font(.system(size: 14, weight: .semibold))

                    Text(tool.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Toggle("", isOn: enabledBinding)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            HStack(spacing: 12) {
                Text("Show in menu")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isEnabled ? .secondary : .tertiary)

                Spacer()

                Toggle("", isOn: showInMenuBinding)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            .padding(.leading, 46)
            .disabled(!isEnabled)
        }
        .padding(14)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        .opacity(isEnabled ? 1 : 0.58)
        .animation(.snappy(duration: 0.16), value: isEnabled)
        .onChange(of: isEnabled) { _, newValue in
            if !newValue {
                showInMenu = false
            }
        }
    }
}


