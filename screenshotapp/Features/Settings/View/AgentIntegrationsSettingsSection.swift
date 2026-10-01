import SwiftUI

/// Settings → AI Agents → Connections: turn each service on with its key
/// (kept in the Keychain). Only turned-on services are ever contacted.
struct AgentIntegrationsSettingsSection: View {
    @ObservedObject var model: AgentIntegrationsViewModel

    @AppStorage(AgentHubSettings.Keys.n8nURL) private var n8nURL = ""
    @State private var keys: [AgentIntegration: String] = [:]

    var body: some View {
        SettingsControlSection(title: AppLocalization.string("agentHub.tab.integrations")) {
            ForEach(Array(AgentIntegration.allCases.enumerated()), id: \.element) { index, integration in
                if index > 0 {
                    SettingsSectionDivider()
                }
                row(integration)
            }

            Text(AppLocalization.string("agentHub.settings.integrationsHint"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ integration: AgentIntegration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                BipMascotView(mood: .idle, size: 26, tint: integration.tint, isInteractive: false)
                Text(integration.name)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { model.isEnabled(integration) },
                    set: { model.setEnabled($0, for: integration) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .disabled(!model.hasKey(integration))
            }

            HStack(spacing: 8) {
                if model.hasKey(integration) {
                    Label(AppLocalization.string("agentHub.settings.keySaved"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 12))
                    Button(AppLocalization.string("agentHub.settings.removeKey")) {
                        model.setKey(nil, for: integration)
                        model.setEnabled(false, for: integration)
                    }
                } else {
                    SecureField(AppLocalization.string("agentHub.settings.key"), text: Binding(
                        get: { keys[integration] ?? "" },
                        set: { keys[integration] = $0 }
                    ))
                    .frame(width: 220)
                    Button(AppLocalization.string("agentHub.ask.saveKey")) {
                        model.setKey(keys[integration], for: integration)
                        model.setEnabled(true, for: integration)
                        keys[integration] = nil
                    }
                    .disabled((keys[integration] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                    if let url = URL(string: integration.keyHelpURL) {
                        Link(AppLocalization.string("agentHub.settings.getKey"), destination: url)
                            .font(.system(size: 12))
                    }
                }
            }
            .padding(.leading, 36)

            if integration == .n8n {
                TextField("https://n8n.example.com", text: $n8nURL)
                    .frame(width: 300)
                    .padding(.leading, 36)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }
}
