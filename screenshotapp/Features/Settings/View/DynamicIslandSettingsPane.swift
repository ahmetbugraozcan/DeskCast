import KeyboardShortcuts
import SwiftUI

struct DynamicIslandSettingsPane: View {
    @ObservedObject var spotifyAccount: SpotifyAccountViewModel
    @AppStorage(ToolboxSettings.Keys.dynamicIslandEnabled)
    private var isEnabled = ToolboxSettings.defaultDynamicIslandEnabled
    @AppStorage(DynamicIslandSettings.Keys.openMode)
    private var openMode = DynamicIslandSettings.defaultOpenMode
    @AppStorage(DynamicIslandSettings.Keys.hoverDelay)
    private var hoverDelay = DynamicIslandSettings.defaultHoverDelay
    @AppStorage(DynamicIslandSettings.Keys.gesturesEnabled)
    private var gesturesEnabled = DynamicIslandSettings.defaultGesturesEnabled
    @AppStorage(DynamicIslandSettings.Keys.hapticsEnabled)
    private var hapticsEnabled = DynamicIslandSettings.defaultHapticsEnabled
    @AppStorage(DynamicIslandSettings.Keys.reopenTarget)
    private var reopenTarget = DynamicIslandSettings.defaultReopenTarget
    @AppStorage(DynamicIslandSettings.Keys.idleContent)
    private var idleContent = DynamicIslandSettings.defaultIdleContent
    @AppStorage(DynamicIslandSettings.Keys.showsTrackChanges)
    private var showsTrackChanges = DynamicIslandSettings.defaultShowsTrackChanges
    @AppStorage(DynamicIslandSettings.Keys.showsAppNotifications)
    private var showsAppNotifications = DynamicIslandSettings.defaultShowsAppNotifications
    @AppStorage(DynamicIslandSettings.Keys.showsSystemNotifications)
    private var showsSystemNotifications = DynamicIslandSettings.defaultShowsSystemNotifications
    @AppStorage(DynamicIslandSettings.Keys.showsBatteryEvents)
    private var showsBatteryEvents = DynamicIslandSettings.defaultShowsBatteryEvents
    @AppStorage(DynamicIslandSettings.Keys.hidesInFullScreen)
    private var hidesInFullScreen = DynamicIslandSettings.defaultHidesInFullScreen
    @AppStorage(DynamicIslandSettings.Keys.displayTarget)
    private var displayTarget = DynamicIslandSettings.defaultDisplayTarget
    @AppStorage(DynamicIslandSettings.Keys.showsInCaptures)
    private var showsInCaptures = DynamicIslandSettings.defaultShowsInCaptures
    @AppStorage(DynamicIslandSettings.Keys.showsOutline)
    private var showsOutline = DynamicIslandSettings.defaultShowsOutline
    @AppStorage(DynamicIslandSettings.Keys.panelShortcutsEnabled)
    private var panelShortcutsEnabled = DynamicIslandSettings.defaultPanelShortcutsEnabled
    @AppStorage(DynamicIslandSettings.Keys.showsSideButtons)
    private var showsSideButtons = DynamicIslandSettings.defaultShowsSideButtons
    @AppStorage(DynamicIslandSettings.Keys.notificationDurationSeconds)
    private var notificationDurationSeconds = DynamicIslandSettings.defaultNotificationDurationSeconds
    @StateObject private var permissionStore = PrivacyPermissionViewModel()
    /// Bumped on reset so the panel list reloads from defaults.
    @State private var panelListID = UUID()

    var body: some View {
        SettingsPage(section: .dynamicIsland) {
            ToolCategorySection(
                title: AppLocalization.string("Tool"),
                tools: [.dynamicIsland]
            )

            FeaturePermissionManagerView(
                store: permissionStore,
                permissions: [.accessibility]
            )

            VStack(alignment: .leading, spacing: 24) {
                openingSection
                idleSection
                notificationsSection

                SettingsControlSection(title: AppLocalization.string("island.settings.panels")) {
                    IslandPanelListEditor()
                        .id(panelListID)
                }

                displaySection
                spotifySection
            }
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.5)

            FeatureResetSection {
                DynamicIslandSettings.resetToDefaults()
                ToolboxSettings.resetTools([.dynamicIsland])
                KeyboardShortcuts.reset(IslandPanel.allCases.map(\.shortcutName))
                panelListID = UUID()
            }
        }
        .onAppear {
            notificationDurationSeconds = DynamicIslandSettings.clampedNotificationDuration(notificationDurationSeconds)
            hoverDelay = DynamicIslandSettings.clampedHoverDelay(hoverDelay)
        }
        .onChange(of: notificationDurationSeconds) { _, newValue in
            notificationDurationSeconds = DynamicIslandSettings.clampedNotificationDuration(newValue)
        }
    }

    // MARK: - Sections

    private var openingSection: some View {
        SettingsControlSection(title: AppLocalization.string("island.settings.opening")) {
            IslandOptionCards(
                options: IslandOpenMode.allCases,
                selection: $openMode,
                title: { AppLocalization.string($0.titleKey) },
                systemImage: \.systemImage
            )

            SettingsSectionDivider()

            SettingsControlRow(
                title: AppLocalization.formatted("island.settings.hoverDelay", hoverDelay)
            ) {
                Slider(value: $hoverDelay, in: DynamicIslandSettings.hoverDelayRange, step: 0.05)
                    .frame(width: 190)
            }
            .disabled(!openMode.expandsOnHover)

            SettingsSectionDivider()

            SettingsToggleRow(
                title: AppLocalization.string("island.settings.gestures"),
                isOn: $gesturesEnabled
            )

            hint("island.settings.gesturesHint")

            SettingsSectionDivider()

            SettingsToggleRow(
                title: AppLocalization.string("island.settings.haptics"),
                isOn: $hapticsEnabled
            )

            SettingsSectionDivider()

            SettingsPickerRow(title: AppLocalization.string("island.settings.reopen")) {
                Picker("", selection: $reopenTarget) {
                    ForEach(IslandReopenTarget.allCases) { target in
                        Text(AppLocalization.string(target.titleKey)).tag(target)
                    }
                }
            }

            SettingsSectionDivider()

            SettingsToggleRow(
                title: AppLocalization.string("island.settings.sideButtons"),
                isOn: $showsSideButtons
            )

            SettingsSectionDivider()

            SettingsToggleRow(
                title: AppLocalization.string("island.settings.panelShortcuts"),
                isOn: $panelShortcutsEnabled
            )

            hint("island.settings.panelShortcutsHint")
        }
    }

    private var idleSection: some View {
        SettingsControlSection(title: AppLocalization.string("island.settings.whileIdle")) {
            IslandOptionCards(
                options: IslandIdleContent.allCases,
                selection: $idleContent,
                title: { AppLocalization.string($0.titleKey) },
                systemImage: \.systemImage
            )

            SettingsSectionDivider()

            SettingsToggleRow(
                title: AppLocalization.string("Announce track changes"),
                isOn: $showsTrackChanges
            )

            hint("Supported players: Music and Spotify. macOS asks once for permission to control them.")
        }
    }

    private var notificationsSection: some View {
        SettingsControlSection(title: AppLocalization.string("Notifications")) {
            SettingsToggleRow(
                title: AppLocalization.string("Show notifications from other apps"),
                isOn: $showsSystemNotifications
            )

            hint("island.settings.systemNotificationsHint")

            SettingsSectionDivider()

            SettingsToggleRow(
                title: AppLocalization.string("Show DeskCast notifications in the island"),
                isOn: $showsAppNotifications
            )

            SettingsSectionDivider()

            SettingsToggleRow(
                title: AppLocalization.string("Show charging and low battery alerts"),
                isOn: $showsBatteryEvents
            )

            SettingsSectionDivider()

            SettingsControlRow(
                title: AppLocalization.formatted("Notification duration: %ld s", notificationDurationSeconds)
            ) {
                Stepper(
                    "",
                    value: $notificationDurationSeconds,
                    in: DynamicIslandSettings.notificationDurationRange
                )
                .labelsHidden()
            }
        }
    }

    private var displaySection: some View {
        SettingsControlSection(title: AppLocalization.string("island.settings.display")) {
            IslandOptionCards(
                options: IslandDisplayTarget.allCases,
                selection: $displayTarget,
                title: { AppLocalization.string($0.titleKey) },
                systemImage: \.systemImage
            )

            SettingsSectionDivider()

            SettingsToggleRow(
                title: AppLocalization.string("island.settings.hideInFullScreen"),
                isOn: $hidesInFullScreen
            )

            SettingsSectionDivider()

            SettingsToggleRow(
                title: AppLocalization.string("island.settings.showInCaptures"),
                isOn: $showsInCaptures
            )

            SettingsSectionDivider()

            SettingsToggleRow(
                title: AppLocalization.string("island.settings.outline"),
                isOn: $showsOutline
            )
        }
    }

    private var spotifySection: some View {
        SettingsControlSection(title: AppLocalization.string("island.spotify.title")) {
            SettingsControlRow(title: AppLocalization.string("island.spotify.clientID")) {
                TextField("", text: $spotifyAccount.clientID, prompt: Text(verbatim: "1a2b3c…"))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                    .disabled(spotifyAccount.isConnected)
            }

            SettingsSectionDivider()

            SettingsControlRow(
                title: AppLocalization.string(
                    spotifyAccount.isConnected ? "island.spotify.connected" : "island.spotify.notConnected"
                )
            ) {
                if spotifyAccount.isConnected {
                    Button(AppLocalization.string("island.spotify.disconnect"), role: .destructive) {
                        spotifyAccount.disconnect()
                    }
                } else {
                    Button(AppLocalization.string(
                        spotifyAccount.isConnecting ? "island.spotify.connecting" : "island.spotify.connect"
                    )) {
                        spotifyAccount.connect()
                    }
                    .disabled(!spotifyAccount.hasClientID || spotifyAccount.isConnecting)
                }
            }

            if let errorMessage = spotifyAccount.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            SettingsSectionDivider()

            VStack(alignment: .leading, spacing: 4) {
                Text(AppLocalization.string("island.spotify.setupSteps"))
                Text(AppLocalization.formatted("island.spotify.redirectHint", SpotifyService.redirectURI))
                    .textSelection(.enabled)
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func hint(_ key: String) -> some View {
        Text(AppLocalization.string(key))
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A row of large selectable cards (icon + caption) for a small set of options.
private struct IslandOptionCards<Option: Identifiable & Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String
    let systemImage: (Option) -> String

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options) { option in
                let isSelected = option == selection

                Button {
                    selection = option
                } label: {
                    VStack(spacing: 7) {
                        Image(systemName: systemImage(option))
                            .font(.system(size: 18, weight: .medium))
                            .frame(height: 22)
                        Text(title(option))
                            .font(.system(size: 11, weight: .semibold))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    .frame(maxWidth: .infinity, minHeight: 68)
                    .padding(.horizontal, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .animation(.easeOut(duration: 0.15), value: selection)
    }
}

/// Launcher order and visibility: drag to reorder, uncheck to hide a panel
/// from the island (and turn off its shortcut).
private struct IslandPanelListEditor: View {
    @State private var order = DynamicIslandSettings.snapshot().panelOrder
    @State private var hidden = DynamicIslandSettings.snapshot().hiddenPanels

    private static let rowHeight: CGFloat = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(AppLocalization.string("island.settings.panelsHint"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 6)

            List {
                ForEach(order) { panel in
                    row(panel)
                }
                .onMove { source, destination in
                    order.move(fromOffsets: source, toOffset: destination)
                    save()
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .environment(\.defaultMinListRowHeight, Self.rowHeight)
            .frame(height: Self.rowHeight * CGFloat(order.count) + 16)
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
    }

    private func row(_ panel: IslandPanel) -> some View {
        let isVisible = !hidden.contains(panel)

        return HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { isVisible },
                set: { newValue in
                    if newValue {
                        hidden.remove(panel)
                    } else if hidden.count < IslandPanel.allCases.count - 1 {
                        // Keep at least one panel.
                        hidden.insert(panel)
                    }
                    save()
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            Image(systemName: panel.systemImage)
                .frame(width: 18)
                .foregroundStyle(isVisible ? Color.accentColor : Color.secondary)

            Text(AppLocalization.string(panel.titleKey))
                .foregroundStyle(isVisible ? .primary : .secondary)

            Spacer()

            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
        }
        .font(.system(size: 13))
        .frame(height: Self.rowHeight)
        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(order.map(\.rawValue), forKey: DynamicIslandSettings.Keys.panelOrder)
        defaults.set(IslandPanel.allCases.filter(hidden.contains).map(\.rawValue), forKey: DynamicIslandSettings.Keys.hiddenPanels)
    }
}
