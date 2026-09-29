import SwiftUI

/// The Focus indicator toggle. Turning it on asks for Focus Status access
/// the first time; macOS only shares whether a Focus is on, not which one.
struct IslandFocusSettingsSection: View {
    @AppStorage(DynamicIslandSettings.Keys.showsFocusIndicator)
    private var showsFocusIndicator = DynamicIslandSettings.defaultShowsFocusIndicator

    @State private var access = FocusAccess.notDetermined
    private let service = SystemFocusStatusService()

    var body: some View {
        SettingsControlSection(title: AppLocalization.string("island.settings.focus")) {
            SettingsToggleRow(
                title: AppLocalization.string("island.settings.focus.toggle"),
                isOn: Binding(
                    get: { showsFocusIndicator },
                    set: { isOn in
                        showsFocusIndicator = isOn
                        if isOn, access == .notDetermined {
                            service.requestAccess { access = $0 }
                        }
                    }
                )
            )

            if showsFocusIndicator, access == .denied {
                SettingsSectionDivider()

                SettingsControlRow(title: AppLocalization.string("island.settings.focus.denied")) {
                    Button(AppLocalization.string("island.settings.focus.openSettings")) {
                        SystemFocusStatusService.openPrivacySettings()
                    }
                }
            }

            Text(AppLocalization.string("island.settings.focus.hint"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { access = service.access }
        // Access may change in System Settings while this pane is open.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            access = service.access
        }
    }
}
