import SwiftUI

/// Settings → AI Agents → Ask Claude: API key or Claude Code, the Anthropic
/// API key (Keychain) and the model the island's chat uses.
struct AgentAskSettingsSection: View {
    @ObservedObject var chat: AgentChatViewModel

    @AppStorage(AgentHubSettings.Keys.claudeModel) private var model = AgentHubSettings.defaultClaudeModel
    @State private var key = ""

    var body: some View {
        SettingsControlSection(title: AppLocalization.string("agentHub.settings.ask")) {
            SettingsControlRow(title: AppLocalization.string("agentHub.settings.backend")) {
                Picker("", selection: Binding(get: { chat.backend }, set: { chat.useBackend($0) })) {
                    Text(AppLocalization.string("agentHub.settings.backend.api")).tag(AgentAskBackend.api)
                    Text(AppLocalization.string("agentHub.settings.backend.claudeCode")).tag(AgentAskBackend.claudeCode)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 260)
            }
            SettingsSectionDivider()
            if chat.backend == .api {
                apiRows
            }

            Text(AppLocalization.string(chat.backend == .api ? "agentHub.settings.askHint" : "agentHub.settings.claudeCodeHint"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            chat.refreshAvailability()
        }
    }

    @ViewBuilder
    private var apiRows: some View {
        SettingsControlRow(title: AppLocalization.string("agentHub.settings.apiKey")) {
            if chat.hasKey {
                HStack(spacing: 8) {
                    Label(AppLocalization.string("agentHub.settings.keySaved"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 12))
                    Button(AppLocalization.string("agentHub.ask.removeKey")) { chat.removeKey() }
                }
            } else {
                HStack(spacing: 8) {
                    SecureField("sk-ant-…", text: $key)
                        .frame(width: 190)
                    Button(AppLocalization.string("agentHub.ask.saveKey")) {
                        chat.saveKey(key)
                        key = ""
                    }
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        SettingsSectionDivider()
        SettingsControlRow(title: AppLocalization.string("agentHub.settings.model")) {
            HStack(spacing: 8) {
                if !chat.models.isEmpty {
                    Picker("", selection: $model) {
                        ForEach(chat.models) { option in
                            Text(option.name).tag(option.id)
                        }
                        if !chat.models.contains(where: { $0.id == model }) {
                            Text(model).tag(model)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                }
                TextField("", text: $model)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 170)
            }
        }
        SettingsSectionDivider()
    }
}
