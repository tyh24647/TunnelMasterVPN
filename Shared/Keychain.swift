import Foundation
import Security

/// Device-only credentials. Persistent references allow Apple's VPN daemon to read secrets.
enum Keychain {
    static let service = "com.tyh24647.TunnelDojo.credentials"

    static var group: String {
        Bundle.main.object(forInfoDictionaryKey: "CredentialGroup") as? String ?? ""
    }

    @discardableResult
    static func save(_ data: Data, key: String) throws -> Data {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccessGroup as String: group,
            kSecAttrAccount as String: key
        ]
        let update = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecItemNotFound {
            var insert = base
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let status = SecItemAdd(insert as CFDictionary, nil)
            guard status == errSecSuccess else {
                throw ServiceError(message: "Unable to store credential (\(status)).")
            }
        } else if update != errSecSuccess {
            throw ServiceError(message: "Unable to update credential (\(update)).")
        }
        var query = base
        query[kSecReturnPersistentRef as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let reference = result as? Data else {
            throw ServiceError(message: "Unable to retrieve credential reference.")
        }
        return reference
    }

    static func read(_ key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccessGroup as String: group,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else {
            return nil
        }
        return result as? Data
    }

    static func remove(_ key: String) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccessGroup as String: group,
            kSecAttrAccount as String: key
        ] as CFDictionary)
    }
}
