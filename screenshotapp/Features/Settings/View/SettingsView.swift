import AppKit
import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @ObservedObject var updateService: AppUpdateService
    let agentHub: AgentHubViewModel

    @AppStorage(ScreenshotShelfSettings.Keys.previewPosition)
    private var previewPositionRaw = ScreenshotShelfSettings.defaultPreviewPosition.rawValue

    @AppStorage(ScreenshotShelfSettings.Keys.stackDirection)
    private var stackDirectionRaw = ScreenshotShelfSettings.defaultStackDirection.rawValue

    @AppStorage(ScreenshotShelfSettings.Keys.maxStackCount)
    private var maxStackCount = ScreenshotShelfSettings.defaultMaxStackCount
    @AppStorage(ScreenshotShelfSettings.Keys.scrollBeyondMaxStack)
    private var scrollBeyondMaxStack = ScreenshotShelfSettings.defaultScrollBeyondMaxStack

    @AppStorage(ScreenshotShelfSettings.Keys.previewDurationSeconds)
    private var previewDurationSeconds = ScreenshotShelfSettings.defaultPreviewDurationSeconds

    @AppStorage(ScreenshotShelfSettings.Keys.neverAutoHide)
    private var neverAutoHide = ScreenshotShelfSettings.defaultNeverAutoHide

    @AppStorage(ScreenshotShelfSettings.Keys.pinScreenshotsByDefault)
    private var pinScreenshotsByDefault = ScreenshotShelfSettings.defaultPinScreenshotsByDefault

    @AppStorage(ScreenshotShelfSettings.Keys.previewDisplayMode)
    private var previewDisplayMode = ScreenshotShelfSettings.defaultPreviewDisplayMode

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

    @AppStorage(ScreenRecordingSettings.Keys.saveDirectoryPath)
    var videoSaveDirectoryPath = ScreenRecordingSettings.defaultSaveDirectoryPath
    @AppStorage(ScreenRecordingSettings.Keys.filenamePrefix)
    private var videoFilenamePrefix = ScreenRecordingSettings.defaultFilenamePrefix
    @AppStorage(ScreenRecordingSettings.Keys.defaultMode)
    private var videoDefaultModeRaw = ScreenRecordingSettings.defaultMode.rawValue
    @AppStorage(ScreenRecordingSettings.Keys.capturesSystemAudio)
    private var videoCapturesSystemAudio = ScreenRecordingSettings.defaultCapturesSystemAudio
    @AppStorage(ScreenRecordingSettings.Keys.capturesMicrophone)
    private var videoCapturesMicrophone = ScreenRecordingSettings.defaultCapturesMicrophone
    @AppStorage(ScreenRecordingSettings.Keys.microphoneDeviceID)
    private var videoMicrophoneDeviceID = ScreenRecordingSettings.defaultMicrophoneDeviceID
    @AppStorage(ScreenRecordingSettings.Keys.showsCursor)
    private var videoShowsCursor = ScreenRecordingSettings.defaultShowsCursor
    @AppStorage(ScreenRecordingSettings.Keys.showsMouseClicks)
    private var videoShowsMouseClicks = ScreenRecordingSettings.defaultShowsMouseClicks
    @AppStorage(ScreenRecordingSettings.Keys.frameRate)
    private var videoFrameRate = ScreenRecordingSettings.defaultFrameRate.rawValue
    @AppStorage(ScreenRecordingSettings.Keys.quality)
    private var videoQualityRaw = ScreenRecordingSettings.defaultQuality.rawValue
    @AppStorage(ScreenRecordingSettings.Keys.codec)
    private var videoCodecRaw = ScreenRecordingSettings.defaultCodec.rawValue
    @AppStorage(ScreenRecordingSettings.Keys.countdownSeconds)
    private var videoCountdownSeconds = ScreenRecordingSettings.defaultCountdownSeconds

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

    @AppStorage(DropShelfSettings.Keys.gridColumnCount)
    private var dropShelfGridColumnCount = DropShelfSettings.defaultGridColumnCount

    @AppStorage(DropShelfSettings.Keys.maxItemCount)
    private var dropShelfMaxItemCount = DropShelfSettings.defaultMaxItemCount

    @AppStorage(DropShelfSettings.Keys.openOnShake)
    private var dropShelfOpenOnShake = DropShelfSettings.defaultOpenOnShake

    @AppStorage(DropShelfSettings.Keys.shakeSensitivity)
    private var dropShelfShakeSensitivity = DropShelfSettings.defaultShakeSensitivity

    @AppStorage(ColorPickerSettings.Keys.copyFormat)
    private var colorCopyFormatRaw = ColorPickerSettings.defaultCopyFormat.rawValue
    @AppStorage(ToolboxSettings.Keys.scrollingCaptureEnabled)
    private var scrollingCaptureEnabled = ToolboxSettings.defaultScrollingCaptureEnabled
    @AppStorage(ToolboxSettings.Keys.pickColorEnabled)
    private var pickColorEnabled = ToolboxSettings.defaultPickColorEnabled

    @AppStorage(ToolboxSettings.Keys.dropShelfEnabled)
    private var dropShelfEnabled = ToolboxSettings.defaultDropShelfEnabled
    @AppStorage(ToolboxSettings.Keys.captureVideoEnabled)
    private var captureVideoEnabled = ToolboxSettings.defaultCaptureVideoEnabled

    @State private var selectedSection: SettingsSection? = .screenshots
    @State private var availableVideoMicrophones: [ScreenRecordingMicrophone] = []
    @StateObject private var permissionStore = PrivacyPermissionViewModel()

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedSection) {
                Section(AppLocalization.string("App")) {
                    ForEach(SettingsSection.appSections) { section in
                        sidebarRow(section)
                    }
                }

                Section(AppLocalization.string("Features")) {
                    ForEach(SettingsSection.featureSections) { section in
                        sidebarRow(section)
                    }
                }
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom) {
                SettingsSidebarFooter()
            }
            // Settings has no reason to collapse its sidebar; dropping the
            // toggle also removes the empty toolbar row above every page.
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(min: 200, ideal: 210, max: 260)
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
        .onAppear {
            clampNumericSettings()
            availableVideoMicrophones = ScreenRecordingSourceService().availableMicrophones()

            #if DEBUG
            if let section = UserDefaults.standard.string(forKey: "DeskCastDemoSettings").flatMap(SettingsSection.init(rawValue:)) {
                selectedSection = section
            }
            #endif
        }
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
        .onChange(of: dropShelfGridColumnCount) { _, newValue in
            dropShelfGridColumnCount = DropShelfSettings.clampedGridColumnCount(newValue)
        }
        .onChange(of: dropShelfMaxItemCount) { _, newValue in
            dropShelfMaxItemCount = DropShelfSettings.clampedMaxItemCount(newValue)
        }
        .onChange(of: dropShelfShakeSensitivity) { _, newValue in
            dropShelfShakeSensitivity = DropShelfSettings.clampedShakeSensitivity(newValue)
        }
    }

    private func sidebarRow(_ section: SettingsSection) -> some View {
        Label {
            Text(section.title)
        } icon: {
            SettingsIconTile(systemImage: section.systemImage, tint: section.tint, size: 20)
        }
        .tag(section)
    }

    @ViewBuilder
    private var selectedPane: some View {
        switch selectedSection ?? .screenshots {
        case .menuBar:
            menuBarPane
        case .screenshots:
            screenshotsPane
        case .videoRecording:
            videoRecordingPane
        case .dropShelf:
            dropShelfPane
        case .finderPath:
            finderPathPane
        case .dynamicIsland:
            DynamicIslandSettingsPane()
        case .aiAgents:
            AgentHubSettingsPane(hub: agentHub)
        case .shortcuts:
            shortcutsPane
        case .about:
            aboutPane
        }
    }

    private var menuBarPane: some View {
        SettingsPage(section: .menuBar) {
            VStack(alignment: .leading, spacing: 24) {
                LanguageSection(selection: $languageRaw)
                MenuLayoutSection(selection: $menuLayoutRaw)
                LaunchAtLoginSection()
            }
        }
    }

    private var screenshotsPane: some View {
        SettingsPage(section: .screenshots) {
            ToolCategorySection(
                title: AppLocalization.string("Tools"),
                tools: [.captureSelectedArea, .captureOCR, .scrollingCapture, .pickColor, .imageSearch]
            )

            FeaturePermissionManagerView(
                store: permissionStore,
                permissions: [.screenRecording]
            )

            VStack(alignment: .leading, spacing: 24) {
                SettingsControlSection(title: AppLocalization.string("Pick Color")) {
                    SettingsSegmentedRow(title: AppLocalization.string("colorPicker.format")) {
                        Picker(AppLocalization.string("colorPicker.format"), selection: $colorCopyFormatRaw) {
                            ForEach(ColorCopyFormat.allCases) { format in
                                Text(format.title).tag(format.rawValue)
                            }
                        }
                    }
                    .disabled(!pickColorEnabled)
                }

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
                        title: AppLocalization.string("Keep older items (scroll)"),
                        isOn: $scrollBeyondMaxStack
                    )

                    SettingsSectionDivider()

                    SettingsToggleRow(
                        title: AppLocalization.string("Pin captures by default"),
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
                    SettingsPickerRow(title: AppLocalization.string("Show previews on")) {
                        Picker(AppLocalization.string("Show previews on"), selection: $previewDisplayMode) {
                            ForEach(ScreenshotShelfDisplayCatalog.options()) { option in
                                Text(option.name).tag(option.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 280)
                    }

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
        SettingsPage(section: .finderPath) {
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
        SettingsPage(section: .dropShelf) {
            ToolCategorySection(
                title: AppLocalization.string("Tool"),
                tools: [.dropShelf]
            )

            FeaturePermissionManagerView(
                store: permissionStore,
                permissions: [.accessibility]
            )

            VStack(alignment: .leading, spacing: 24) {
                DropShelfLayoutSettingsSection(
                    layoutModeRaw: $dropShelfLayoutModeRaw,
                    itemSizeRaw: $dropShelfItemSizeRaw,
                    gridColumnCount: $dropShelfGridColumnCount,
                    customItemWidth: $dropShelfCustomItemWidth
                )

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
                                in: DropShelfSettings.shakeSensitivityDoubleRange,
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
        SettingsPage(section: .shortcuts) {
            Form {
                Section(AppLocalization.string("Screenshots")) {
                    KeyboardShortcuts.Recorder(
                        AppLocalization.string("Selected area:"),
                        name: .captureSelectedArea
                    )

                    KeyboardShortcuts.Recorder(
                        AppLocalization.string("shortcuts.scrollingCapture"),
                        name: .scrollingCapture
                    )
                    .disabled(!scrollingCaptureEnabled)

                    KeyboardShortcuts.Recorder(
                        AppLocalization.string("shortcuts.pickColor"),
                        name: .pickColor
                    )
                    .disabled(!pickColorEnabled)

                }

                Section(AppLocalization.string("Video Recording")) {
                    KeyboardShortcuts.Recorder(
                        AppLocalization.string("Video capture:"),
                        name: .captureVideo
                    )
                    .disabled(!captureVideoEnabled)
                }

                Section(AppLocalization.string("Files")) {
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
}

// Resets touch only UserDefaults and shortcuts, so they live outside the view body.
extension SettingsView {
    private func resetScreenshotSettings() {
        ScreenshotShelfSettings.resetToDefaults()
        ToolboxSettings.resetTools([.captureSelectedArea, .captureOCR, .scrollingCapture, .pickColor, .imageSearch])
        UserDefaults.standard.set(ColorPickerSettings.defaultCopyFormat.rawValue, forKey: ColorPickerSettings.Keys.copyFormat)
        KeyboardShortcuts.reset(.captureSelectedArea, .scrollingCapture, .pickColor)
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

private extension SettingsView {
    var videoRecordingPane: some View {
        SettingsPage(section: .videoRecording) {
            ToolCategorySection(
                title: AppLocalization.string("Tool"),
                tools: [.captureVideo]
            )

            FeaturePermissionManagerView(
                store: permissionStore,
                permissions: [.screenRecording, .microphone]
            )

            VStack(alignment: .leading, spacing: 24) {
                SettingsControlSection(title: AppLocalization.string("Recording")) {
                    SettingsSegmentedRow(title: AppLocalization.string("Default mode")) {
                        Picker(AppLocalization.string("Default mode"), selection: $videoDefaultModeRaw) {
                            Text(AppLocalization.string("Full Screen"))
                                .tag(ScreenRecordingMode.entireScreen.rawValue)
                            Text(AppLocalization.string("Selected Area"))
                                .tag(ScreenRecordingMode.selectedArea.rawValue)
                        }
                    }

                    SettingsSectionDivider()

                    SettingsSegmentedRow(title: AppLocalization.string("Quality")) {
                        Picker(AppLocalization.string("Quality"), selection: $videoQualityRaw) {
                            ForEach(ScreenRecordingQuality.allCases) { quality in
                                Text(ScreenRecordingControlView.qualityTitle(quality)).tag(quality.rawValue)
                            }
                        }
                    }

                    SettingsSectionDivider()

                    SettingsSegmentedRow(title: AppLocalization.string("Codec")) {
                        Picker(AppLocalization.string("Codec"), selection: $videoCodecRaw) {
                            ForEach(ScreenRecordingCodec.allCases) { codec in
                                Text(ScreenRecordingControlView.codecTitle(codec)).tag(codec.rawValue)
                            }
                        }
                    }

                    SettingsSectionDivider()

                    SettingsSegmentedRow(title: AppLocalization.string("Frame rate")) {
                        Picker(AppLocalization.string("Frame rate"), selection: $videoFrameRate) {
                            ForEach(ScreenRecordingFrameRate.allCases) { frameRate in
                                Text("\(frameRate.rawValue)").tag(frameRate.rawValue)
                            }
                        }
                    }

                    SettingsSectionDivider()

                    SettingsSegmentedRow(title: AppLocalization.string("Countdown")) {
                        Picker(AppLocalization.string("Countdown"), selection: $videoCountdownSeconds) {
                            ForEach(ScreenRecordingSettings.countdownOptions, id: \.self) { seconds in
                                Text(ScreenRecordingControlView.countdownTitle(seconds)).tag(seconds)
                            }
                        }
                    }

                    SettingsSectionDivider()

                    SettingsToggleRow(
                        title: AppLocalization.string("Show cursor"),
                        isOn: $videoShowsCursor
                    )

                    SettingsSectionDivider()

                    SettingsToggleRow(
                        title: AppLocalization.string("Show mouse clicks"),
                        isOn: $videoShowsMouseClicks
                    )
                }

                SettingsControlSection(title: AppLocalization.string("Audio")) {
                    SettingsToggleRow(
                        title: AppLocalization.string("Record system audio"),
                        isOn: $videoCapturesSystemAudio
                    )

                    SettingsSectionDivider()

                    SettingsToggleRow(
                        title: AppLocalization.string("Record microphone"),
                        isOn: $videoCapturesMicrophone
                    )

                    if videoCapturesMicrophone {
                        SettingsSectionDivider()

                        SettingsPickerRow(title: AppLocalization.string("Microphone")) {
                            Picker(AppLocalization.string("Microphone"), selection: $videoMicrophoneDeviceID) {
                                Text(AppLocalization.string("System Default")).tag("")
                                ForEach(availableVideoMicrophones) { microphone in
                                    Text(microphone.name).tag(microphone.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: 280)
                        }
                    }
                }

                SettingsControlSection(title: AppLocalization.string("Files")) {
                    SettingsControlRow(title: AppLocalization.string("Save to")) {
                        HStack(spacing: 8) {
                            Text(videoSaveDirectoryPath)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: 260, alignment: .trailing)

                            Button(AppLocalization.string("Choose...")) {
                                chooseVideoSaveDirectory()
                            }
                        }
                    }

                    SettingsSectionDivider()

                    SettingsControlRow(title: AppLocalization.string("Filename prefix")) {
                        TextField(
                            AppLocalization.string("Filename prefix"),
                            text: $videoFilenamePrefix
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                    }
                }
            }
            .disabled(!captureVideoEnabled)
            .opacity(captureVideoEnabled ? 1 : 0.5)

            FeatureResetSection {
                resetVideoRecordingSettings()
            }
        }
    }
}

private struct MenuLayoutSection: View {
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SettingsSectionHeader(title: AppLocalization.string("Layout"))

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 16) {
                    Text(AppLocalization.string("Menu layout"))
                        .font(.system(size: 13, weight: .medium))

                    Spacer()

                    Picker(AppLocalization.string("Menu layout"), selection: $selection) {
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
            .settingsCard()
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

struct ToolCategorySection: View {
    let title: String
    let tools: [ToolboxToolID]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SettingsSectionHeader(title: title)

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
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                SettingsIconTile(
                    systemImage: tool.systemImage,
                    tint: isEnabled ? tool.settingsTint : .gray,
                    size: 34
                )

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
            .padding(14)

            Divider()
                .opacity(0.6)

            HStack(spacing: 8) {
                Image(systemName: "menubar.rectangle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(AppLocalization.string("Show in menu"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isEnabled ? .secondary : .tertiary)

                Spacer()

                Toggle("", isOn: showInMenuBinding)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.025))
            .disabled(!isEnabled)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .settingsCard()
        .opacity(isEnabled ? 1 : 0.58)
        .animation(.snappy(duration: 0.16), value: isEnabled)
        .onChange(of: isEnabled) { _, newValue in
            if !newValue {
                showInMenu = false
            }
        }
    }
}

/// App icon, name and version pinned under the Settings sidebar.
private struct SettingsSidebarFooter: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(AppConstants.displayName)
                    .font(.system(size: 12.5, weight: .semibold))
                Text(AppLocalization.formatted("settings.version", version))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
