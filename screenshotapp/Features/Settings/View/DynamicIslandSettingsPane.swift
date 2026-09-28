import KeyboardShortcuts
import SwiftUI

struct DynamicIslandSettingsPane: View {
    @ObservedObject var spotifyAccount: SpotifyAccountViewModel
    @AppStorage(ToolboxSettings.Keys.dynamicIslandEnabled)
    private var isEnabled = ToolboxSettings.defaultDynamicIslandEnabled
    @AppStorage(DynamicIslandSettings.Keys.showsNowPlaying)
    private var showsNowPlaying = DynamicIslandSettings.defaultShowsNowPlaying
    @AppStorage(DynamicIslandSettings.Keys.showsTrackChanges)
    private var showsTrackChanges = DynamicIslandSettings.defaultShowsTrackChanges
    @AppStorage(DynamicIslandSettings.Keys.showsAppNotifications)
    private var showsAppNotifications = DynamicIslandSettings.defaultShowsAppNotifications
    @AppStorage(DynamicIslandSettings.Keys.showsSystemNotifications)
    private var showsSystemNotifications = DynamicIslandSettings.defaultShowsSystemNotifications
    @AppStorage(DynamicIslandSettings.Keys.showsBatteryEvents)
    private var showsBatteryEvents = DynamicIslandSettings.defaultShowsBatteryEvents
    @AppStorage(DynamicIslandSettings.Keys.expandsOnHover)
    private var expandsOnHover = DynamicIslandSettings.defaultExpandsOnHover
    @AppStorage(DynamicIslandSettings.Keys.panelShortcutsEnabled)
    private var panelShortcutsEnabled = DynamicIslandSettings.defaultPanelShortcutsEnabled
    @AppStorage(DynamicIslandSettings.Keys.showsSideButtons)
    private var showsSideButtons = DynamicIslandSettings.defaultShowsSideButtons
    @AppStorage(DynamicIslandSettings.Keys.notificationDurationSeconds)
    private var notificationDurationSeconds = DynamicIslandSettings.defaultNotificationDurationSeconds
    @StateObject private var permissionStore = PrivacyPermissionViewModel()

    var body: some View {
        SettingsPage(
            title: AppLocalization.string("Dynamic Island"),
            systemImage: ToolboxToolID.dynamicIsland.systemImage
        ) {
            ToolCategorySection(
                title: AppLocalization.string("Tool"),
                tools: [.dynamicIsland]
            )

            FeaturePermissionManagerView(
                store: permissionStore,
                permissions: [.accessibility]
            )

            VStack(alignment: .leading, spacing: 24) {
                SettingsControlSection(title: AppLocalization.string("Now Playing")) {
                    SettingsToggleRow(
                        title: AppLocalization.string("Show the playing song"),
                        isOn: $showsNowPlaying
                    )

                    SettingsSectionDivider()

                    SettingsToggleRow(
                        title: AppLocalization.string("Announce track changes"),
                        isOn: $showsTrackChanges
                    )
                    .disabled(!showsNowPlaying)

                    SettingsSectionDivider()

                    Text(AppLocalization.string("Supported players: Music and Spotify. macOS asks once for permission to control them."))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                SettingsControlSection(title: AppLocalization.string("Notifications")) {
                    SettingsToggleRow(
                        title: AppLocalization.string("Show notifications from other apps"),
                        isOn: $showsSystemNotifications
                    )

                    SettingsSectionDivider()

                    Text(AppLocalization.string("island.settings.systemNotificationsHint"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)

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

                SettingsControlSection(title: AppLocalization.string("Behavior")) {
                    SettingsToggleRow(
                        title: AppLocalization.string("Expand on hover"),
                        isOn: $expandsOnHover
                    )

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

                    Text(AppLocalization.string("island.settings.panelShortcutsHint"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.5)

            FeatureResetSection {
                DynamicIslandSettings.resetToDefaults()
                ToolboxSettings.resetTools([.dynamicIsland])
                KeyboardShortcuts.reset(IslandPanel.allCases.map(\.shortcutName))
            }
        }
        .onAppear {
            notificationDurationSeconds = DynamicIslandSettings.clampedNotificationDuration(notificationDurationSeconds)
        }
        .onChange(of: notificationDurationSeconds) { _, newValue in
            notificationDurationSeconds = DynamicIslandSettings.clampedNotificationDuration(newValue)
        }
    }
}
