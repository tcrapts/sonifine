import Foundation
import Security

/// Keeps the keys of the Spotify connections.
protocol SecretStore: AnyObject {
    func read(_ key: String) -> String?
    /// Returns whether the value was stored.
    @discardableResult func save(_ value: String, for key: String) -> Bool
    func delete(_ key: String)
}

/// The Keychain of this device. Items are readable after the first unlock, so
/// the app finds its keys when it starts in the background.
final class KeychainStore: SecretStore {
    func read(_ key: String) -> String? {
        var result: AnyObject?
        let status = SecItemCopyMatching(query(key).merging([kSecReturnData: true]) { $1 } as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func save(_ value: String, for key: String) -> Bool {
        delete(key)
        let item = query(key).merging([
            kSecValueData: Data(value.utf8),
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]) { $1 }
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    func delete(_ key: String) {
        SecItemDelete(query(key) as CFDictionary)
    }

    /// Items are found by account name alone, as the first versions stored them.
    private func query(_ key: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrAccount: key]
    }
}
