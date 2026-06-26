import Foundation
import Security

/// Minimal Keychain wrapper for storing secrets (API keys, license) by account name,
/// so they never sit in plaintext in UserDefaults. Reads don't prompt as long as the app
/// is signed with a stable identity (Apple Development / Developer ID).
enum Keychain {
    private static let service = "com.babelbar.secrets"

    // Account names for the secrets we store.
    static let apiKey = "apiKey"
    static let apiKey2 = "apiKey2"
    static let transcriptionAPIKey = "transcriptionAPIKey"
    static let license = "license"

    /// Store (or, for an empty value, remove) a secret.
    static func set(_ value: String, for account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }   // empty == just delete
        var attrs = base
        attrs[kSecValueData as String] = Data(value.utf8)
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attrs as CFDictionary, nil)
    }

    /// Read a secret (empty string if absent).
    static func get(_ account: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let str = String(data: data, encoding: .utf8) else {
            return ""
        }
        return str
    }

    static func delete(_ account: String) { set("", for: account) }
}
