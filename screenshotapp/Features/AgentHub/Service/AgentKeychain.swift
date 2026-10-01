import Foundation
import Security

/// API keys of the AI agents hub (Anthropic and the integrations), kept in
/// the login Keychain: this device only, never synced, readable while the
/// Mac is unlocked. Nothing is written to disk or to UserDefaults.
nonisolated enum AgentSecret: String, CaseIterable, Sendable {
    case anthropic
    case stripe
    case n8n
    case github
    case vercel
    case resend
    case notion
    case calcom
}

@MainActor
protocol AgentSecretStoring: AnyObject {
    func value(for secret: AgentSecret) -> String?
    func set(_ value: String?, for secret: AgentSecret)
}

/// Reads each key once, then serves it from memory.
final class AgentKeychain: AgentSecretStoring {
    private static let service = "com.ahmetbugraozcan.screenshotapp.agentHub"
    private var cache: [AgentSecret: String?] = [:]

    func value(for secret: AgentSecret) -> String? {
        if let cached = cache[secret] {
            return cached
        }
        let value = Self.read(secret)
        cache[secret] = value
        return value
    }

    func set(_ value: String?, for secret: AgentSecret) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        let stored = trimmed?.isEmpty == false ? trimmed : nil
        cache[secret] = stored
        Self.delete(secret)
        if let stored {
            Self.write(stored, for: secret)
        }
    }

    private static func baseQuery(_ secret: AgentSecret) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: secret.rawValue
        ]
    }

    private static func read(_ secret: AgentSecret) -> String? {
        var query = baseQuery(secret)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func write(_ value: String, for secret: AgentSecret) {
        var item = baseQuery(secret)
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        item[kSecAttrSynchronizable as String] = false
        SecItemAdd(item as CFDictionary, nil)
    }

    private static func delete(_ secret: AgentSecret) {
        SecItemDelete(baseQuery(secret) as CFDictionary)
    }
}
