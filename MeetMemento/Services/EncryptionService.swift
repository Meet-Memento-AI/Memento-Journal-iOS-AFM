//
//  EncryptionService.swift
//  MeetMemento
//
//  Handles PIN-based encryption for journal content using AES-GCM.
//  Derives encryption keys from the user's PIN using PBKDF2.
//

import CryptoKit
import Foundation
import Security
import CommonCrypto

class EncryptionService {
    static let shared = EncryptionService()

    private let keychain: KeychainStoring
    private let saltKeychainKey = "com.sebastianmendo.MeetMemento.encryptionSalt"
    private let saltLength = 32 // 256 bits
    private let pbkdf2Iterations: UInt32 = 100_000 // OWASP recommended minimum
    private let derivedKeyLength = 32 // 256 bits for AES-256

    /// `keychain` defaults to the real Keychain; tests inject a mock so no
    /// suite run touches the real Keychain (which unit tests lack the
    /// entitlements for anyway).
    init(keychain: KeychainStoring = SystemKeychainStore()) {
        self.keychain = keychain
    }

    // MARK: - Key Derivation

    /// Derives a 256-bit encryption key from PIN using PBKDF2-SHA256 with stored salt
    /// Uses 100,000 iterations as recommended by OWASP for password-based key derivation
    func deriveKey(from pin: String) -> SymmetricKey? {
        guard let salt = getOrCreateSalt(),
              let pinData = pin.data(using: .utf8) else {
            return nil
        }

        // Use PBKDF2-SHA256 for secure key derivation
        var derivedKeyData = Data(count: derivedKeyLength)
        let derivationStatus = derivedKeyData.withUnsafeMutableBytes { derivedKeyBytes in
            pinData.withUnsafeBytes { pinBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pinBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        pinData.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        pbkdf2Iterations,
                        derivedKeyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        derivedKeyLength
                    )
                }
            }
        }

        guard derivationStatus == kCCSuccess else {
            AppLogger.log("PBKDF2 key derivation failed with status: \(derivationStatus)")
            return nil
        }

        return SymmetricKey(data: derivedKeyData)
    }

    // MARK: - Encryption/Decryption

    /// Encrypts plaintext using AES-GCM with PIN-derived key
    /// - Parameters:
    ///   - plaintext: The text to encrypt
    ///   - pin: The user's PIN for key derivation
    /// - Returns: Combined nonce + ciphertext + tag data, or nil on failure
    func encrypt(_ plaintext: String, withPIN pin: String) -> Data? {
        guard let key = deriveKey(from: pin),
              let data = plaintext.data(using: .utf8) else {
            return nil
        }

        do {
            let sealedBox = try AES.GCM.seal(data, using: key)
            // Return combined format: nonce || ciphertext || tag
            return sealedBox.combined
        } catch {
            AppLogger.log("⚠️ [EncryptionService] Encryption failed: \(error)")
            return nil
        }
    }

    /// Decrypts ciphertext using AES-GCM with PIN-derived key
    /// - Parameters:
    ///   - ciphertext: Combined nonce + ciphertext + tag data
    ///   - pin: The user's PIN for key derivation
    /// - Returns: Decrypted plaintext, or nil on failure
    func decrypt(_ ciphertext: Data, withPIN pin: String) -> String? {
        guard let key = deriveKey(from: pin) else {
            return nil
        }

        do {
            let sealedBox = try AES.GCM.SealedBox(combined: ciphertext)
            let decryptedData = try AES.GCM.open(sealedBox, using: key)
            return String(data: decryptedData, encoding: .utf8)
        } catch {
            AppLogger.log("⚠️ [EncryptionService] Decryption failed: \(error)")
            return nil
        }
    }

    /// Validates that the PIN can decrypt existing data
    /// - Parameters:
    ///   - ciphertext: Some encrypted data to test against
    ///   - pin: The PIN to validate
    /// - Returns: True if decryption succeeds
    func validatePIN(_ pin: String, against ciphertext: Data) -> Bool {
        return decrypt(ciphertext, withPIN: pin) != nil
    }

    // MARK: - Salt Management (stored in Keychain)

    /// Gets existing salt or creates a new one if none exists
    private func getOrCreateSalt() -> Data? {
        // Try to retrieve existing salt
        if let existingSalt = getSaltFromKeychain() {
            return existingSalt
        }

        // Generate new random salt
        var salt = Data(count: saltLength)
        let result = salt.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, saltLength, buffer.baseAddress!)
        }

        guard result == errSecSuccess else {
            AppLogger.log("⚠️ [EncryptionService] Failed to generate random salt")
            return nil
        }

        // Store in Keychain
        if saveSaltToKeychain(salt) {
            return salt
        }

        return nil
    }

    private func getSaltFromKeychain() -> Data? {
        keychain.data(forAccount: saltKeychainKey)
    }

    private func saveSaltToKeychain(_ salt: Data) -> Bool {
        keychain.save(salt, forAccount: saltKeychainKey)
    }

    /// Deletes the encryption salt from Keychain (used on PIN change or account deletion)
    func deleteSalt() {
        keychain.delete(forAccount: saltKeychainKey)
    }

    /// Clears all encryption data (salt). Call this when PIN is changed.
    func clearAll() {
        deleteSalt()
    }
}
