import SwiftUI

/// Settings → AI Agents: the Claude Code hooks (installed only after the
/// user reviewed the diff), how permission requests are handled, and Bip.
struct AgentHubSettingsPane: View {
    @ObservedObject var hub: AgentHubViewModel
    @ObservedObject var chat: AgentChatViewModel

    @AppStorage(AgentHubSettings.Keys.enabled) private var enabled = AgentHubSettings.defaultEnabled
    @AppStorage(AgentHubSettings.Keys.approvalTimeout) private var approvalTimeout = AgentHubSettings.defaultApprovalTimeout
    @AppStorage(AgentHubSettings.Keys.opensForAttention) private var opensForAttention = AgentHubSettings.defaultOpensForAttention
    @AppStorage(AgentHubSettings.Keys.soundsEnabled) private var soundsEnabled = AgentHubSettings.defaultSoundsEnabled
    @AppStorage(AgentHubSettings.Keys.soundVolume) private var soundVolume = AgentHubSettings.defaultSoundVolume
    @AppStorage(AgentHubSettings.Keys.showsMascot) private var showsMascot = AgentHubSettings.defaultShowsMascot

    @State private var previewMood = BipMood.idle

    private static let previewMoods: [BipMood] = [
        .idle, .thinking, .working, .approval, .question, .error, .finished, .rateLimited, .sleeping
    ]

    var body: some View {
        SettingsPage(section: .aiAgents) {
            VStack(alignment: .leading, spacing: 24) {
                claudeCodeSection
                AgentAskSettingsSection(chat: chat)
                bipSection
            }
        }
        .onAppear { hub.refreshHookStatus() }
    }

    private var claudeCodeSection: some View {
        SettingsControlSection(title: "Claude Code") {
            SettingsToggleRow(title: AppLocalization.string("agentHub.settings.enabled"), isOn: $enabled)
            SettingsSectionDivider()

            SettingsControlRow(title: AppLocalization.string("agentHub.settings.hooks")) {
                HStack(spacing: 8) {
                    Label(
                        AppLocalization.string("agentHub.settings.hooks.\(hub.hooksInstalled ? "installed" : "missing")"),
                        systemImage: hub.hooksInstalled ? "checkmark.circle.fill" : "circle.dashed"
                    )
                    .foregroundStyle(hub.hooksInstalled ? .green : .secondary)
                    .font(.system(size: 12))

                    if !hub.hooksInstalled || hub.hooksNeedUpdate {
                        Button(AppLocalization.string("agentHub.settings.hooks.\(hub.hooksInstalled ? "update" : "install")")) {
                            hub.prepareInstall()
                        }
                    }
                    if hub.hooksInstalled {
                        Button(AppLocalization.string("agentHub.settings.hooks.remove")) {
                            hub.prepareUninstall()
                        }
                    }
                }
            }

            if let change = hub.pendingHookChange {
                pendingChange(change)
            }

            if let error = hub.hookError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            SettingsSectionDivider()
            SettingsControlRow(title: AppLocalization.string("agentHub.settings.timeout")) {
                Stepper(
                    AppLocalization.formatted("agentHub.settings.seconds", approvalTimeout),
                    value: $approvalTimeout,
                    in: AgentHubSettings.approvalTimeoutRange,
                    step: 10
                )
                .font(.system(size: 12).monospacedDigit())
            }
            SettingsSectionDivider()
            SettingsToggleRow(title: AppLocalization.string("agentHub.settings.opensForAttention"), isOn: $opensForAttention)

            Text(AppLocalization.string("agentHub.settings.hint"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func pendingChange(_ change: ClaudeHookChange) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppLocalization.string(hub.pendingChangeTitleKey))
                .font(.system(size: 12, weight: .semibold))

            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(change.diff.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .foregroundStyle(line.hasPrefix("+") ? .green : .red)
                    }
                }
                .font(.system(size: 11, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(8)
            }
            .frame(height: 160)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.25)))

            HStack {
                Text(AppLocalization.string("agentHub.hooks.backupNote"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(AppLocalization.string("agentHub.cancel")) { hub.cancelPendingChange() }
                Button(AppLocalization.string("agentHub.hooks.apply")) { hub.confirmPendingChange() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    private var bipSection: some View {
        SettingsControlSection(title: "Bip") {
            HStack(spacing: 16) {
                BipMascotView(mood: previewMood, size: 72)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black))

                VStack(alignment: .leading, spacing: 6) {
                    Text(AppLocalization.string("agentHub.settings.bip"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Picker("", selection: $previewMood) {
                        ForEach(Self.previewMoods, id: \.self) { mood in
                            Text(AppLocalization.string("agentHub.mood.\(mood.rawValue)")).tag(mood)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            SettingsSectionDivider()
            SettingsToggleRow(title: AppLocalization.string("agentHub.settings.mascot"), isOn: $showsMascot)
            SettingsSectionDivider()
            SettingsToggleRow(title: AppLocalization.string("agentHub.settings.sounds"), isOn: $soundsEnabled)
            SettingsSectionDivider()
            SettingsControlRow(title: AppLocalization.string("agentHub.settings.volume")) {
                Slider(value: $soundVolume, in: AgentHubSettings.soundVolumeRange) { editing in
                    if !editing { BipSoundPlayer.shared.play(.finished) }
                }
                .frame(width: 190)
                .disabled(!soundsEnabled)
            }
        }
    }
}
