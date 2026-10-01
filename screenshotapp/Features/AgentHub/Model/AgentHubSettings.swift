import Foundation

/// Settings of the AI agents hub (Claude Code hooks, chat, integrations).
nonisolated enum AgentHubSettings {
    enum Keys {
        static let enabled = "agentHub.enabled"
        static let approvalTimeout = "agentHub.approvalTimeout"
        static let opensForAttention = "agentHub.opensForAttention"
        static let soundsEnabled = "agentHub.soundsEnabled"
        static let soundVolume = "agentHub.soundVolume"
        static let showsMascot = "agentHub.showsMascot"
        static let claudeModel = "agentHub.claudeModel"
        static let activeIntegrations = "agentHub.activeIntegrations"
        static let n8nURL = "agentHub.n8nURL"
    }

    static let approvalTimeoutRange = 30...550
    static let soundVolumeRange = 0.0...1.0

    static let defaultEnabled = true
    /// Seconds DeskCast holds a permission request before Claude Code asks
    /// in the terminal.
    static let defaultApprovalTimeout = 110
    static let defaultOpensForAttention = true
    static let defaultSoundsEnabled = true
    static let defaultSoundVolume = 0.5
    static let defaultShowsMascot = true
    static let defaultClaudeModel = "claude-opus-5-5"

    static func registerDefaults(in defaults: UserDefaults) {
        defaults.register(defaults: [
            Keys.enabled: defaultEnabled,
            Keys.approvalTimeout: defaultApprovalTimeout,
            Keys.opensForAttention: defaultOpensForAttention,
            Keys.soundsEnabled: defaultSoundsEnabled,
            Keys.soundVolume: defaultSoundVolume,
            Keys.showsMascot: defaultShowsMascot,
            Keys.claudeModel: defaultClaudeModel,
            Keys.activeIntegrations: [String](),
            Keys.n8nURL: ""
        ])
    }

    static func approvalTimeout(in defaults: UserDefaults) -> Int {
        let value = defaults.integer(forKey: Keys.approvalTimeout)
        return min(max(value, approvalTimeoutRange.lowerBound), approvalTimeoutRange.upperBound)
    }

    static func soundVolume(in defaults: UserDefaults) -> Double {
        min(max(defaults.double(forKey: Keys.soundVolume), soundVolumeRange.lowerBound), soundVolumeRange.upperBound)
    }

    static func claudeModel(in defaults: UserDefaults) -> String {
        let model = defaults.string(forKey: Keys.claudeModel)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return model.isEmpty ? defaultClaudeModel : model
    }
}
