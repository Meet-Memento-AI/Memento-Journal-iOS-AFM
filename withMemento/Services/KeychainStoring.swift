//
//  KeychainStoring.swift
//  MeetMemento
//
//  Testable seam over Keychain access (spec-011 R1), so EncryptionService
//  and SecurityService can be unit tested without touching the real
//  Keychain (which unit tests don't have entitlements for anyway).
//

import Foundation
import Security

protocol KeychainStoring {
    func data(forAccount account: String) -> Data?
    @discardableResult func save(_ data: Data, forAccount account: String) -> Bool
    func delete(forAccount account: String)
}

/// Real Keychain-backed implementation — identical query shape to what
/// EncryptionService/SecurityService used inline before this seam existed,
/// just parameterized by account key.
final class SystemKeychainStore: KeychainStoring {
    func data(forAccount account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return data
    }

    @discardableResult
    func save(_ data: Data, forAccount account: String) -> Bool {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            AppLogger.log("⚠️ [SystemKeychainStore] Failed to save item for \(account): \(status)")
        }
        return status == errSecSuccess
    }

    func delete(forAccount account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
