//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation
import Security

/// A minimal wrapper over the macOS Keychain for storing small secrets (API tokens) as generic
/// passwords under a fixed service. Secrets never go in `UserDefaults`/`AppSettings` in plaintext.
nonisolated enum Keychain {

    /// Keychain service (shared by all Flowplan secrets); the `account` distinguishes them.
    private static let service = "io.apparata.Flowplan"

    /// Well-known account names for the secrets Flowplan stores.
    enum Account {
        /// The GitHub Personal Access Token used for issue import.
        static let githubToken = "github.pat"
    }

    /// Stores (or replaces) a UTF-8 secret for `account`. Passing an empty string deletes it.
    @discardableResult
    static func set(_ value: String, account: String) -> Bool {
        guard !value.isEmpty else { return delete(account: account) }
        guard let data = value.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return true }
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
        }
        return false
    }

    /// Returns the UTF-8 secret for `account`, or `nil` if none is stored.
    static func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }

    /// Removes the secret for `account`. Returns `true` if it was removed or already absent.
    @discardableResult
    static func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
