//
//  EncryptionService.swift
//  MeetMemento
//
//  Encrypts journal content with AES-GCM under a random, Keychain-resident
//  data-encryption key (DEK).
//
//  The DEK is the current design. Journal content used to be encrypted under
//  PBKDF2(PIN, salt), which made the PIN do two unrelated jobs at once — the
//  unlock gate AND the key. That coupling had two consequences:
//
//    1. Changing or setting a PIN silently orphaned every existing entry,
//       because the key changed underneath them. That is why there was no way
//       to change the PIN in Settings, even though onboarding promised one.
//    2. A Keychain miss on the PIN meant the journal could not be read at all,
//       with no recovery path.
//
//  Now: the DEK is generated once, stored in the Keychain as
//  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, and never changes. The PIN
//  is purely an app-access gate. Changing, setting, or removing it is free.
//
//  Legacy PIN-derived content is migrated lazily and per-entry by
//  `EncryptionMigrator` — see `decryptMigrating(_:legacyPIN:)`. The PBKDF2 path
//  below exists ONLY to read that legacy content and must not be used for new
//  writes.
//

import CryptoKit
import Foundation
import Security
import CommonCrypto

class EncryptionService {
    static let shared = EncryptionService()

    private let keychain: KeychainStoring
    private let saltKeychainKey = "com.sebastianmendo.MeetMemento.encryptionSalt"
    private let dataKeyKeychainKey = "com.sebastianmendo.MeetMemento.dataEncryptionKey"
    private let saltLength = 32 // 256 bits
    private let dataKeyLength = 32 // 256 bits for AES-256
    private let pbkdf2Iterations: UInt32 = 100_000 // OWASP recommended minimum
    private let derivedKeyLength = 32 // 256 bits for AES-256

    /// `keychain` defaults to the real Keychain; tests inject a mock so no
    /// suite run touches the real Keychain (which unit tests lack the
    /// entitlements for anyway).
    init(keychain: KeychainStoring = SystemKeychainStore()) {
        self.keychain = keychain
    }

    // MARK: - Data Encryption Key (current design)

    private let dataKeyLock = NSLock()
    private var cachedDataKey: SymmetricKey?

    /// True when a DEK already exists in the Keychain. Does not create one.
    var hasDataKey: Bool {
        keychain.data(forAccount: dataKeyKeychainKey) != nil
    }

    /// The random 256-bit data-encryption key, creating and persisting one on
    /// first use. Unlike the PBKDF2 path this is a Keychain read, not a
    /// derivation, so it is cheap enough to call per operation.
    ///
    /// Returns nil only if the Keychain is unreadable or a new key cannot be
    /// persisted — never a silently-unpersisted key, which would encrypt
    /// content nothing could ever decrypt again.
    func dataKey() -> SymmetricKey? {
        dataKeyLock.lock()
        defer { dataKeyLock.unlock() }

        if let cached = cachedDataKey { return cached }

        if let existing = keychain.data(forAccount: dataKeyKeychainKey) {
            guard existing.count == dataKeyLength else {
                AppLogger.log("⚠️ [EncryptionService] Stored data key has unexpected length \(existing.count); refusing to use it")
                return nil
            }
            let key = SymmetricKey(data: existing)
            cachedDataKey = key
            return key
        }

        var raw = Data(count: dataKeyLength)
        let status = raw.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, dataKeyLength, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            AppLogger.log("⚠️ [EncryptionService] Failed to generate a random data key")
            return nil
        }
        guard keychain.save(raw, forAccount: dataKeyKeychainKey) else {
            AppLogger.log("⚠️ [EncryptionService] Failed to persist the data key; refusing to encrypt with an ephemeral key")
            return nil
        }

        let key = SymmetricKey(data: raw)
        cachedDataKey = key
        AppLogger.log("🔐 [EncryptionService] Generated a new data-encryption key")
        return key
    }

    /// Encrypts plaintext under the data key. This is the path all new writes use.
    func encrypt(_ plaintext: String) -> Data? {
        guard let key = dataKey(), let data = plaintext.data(using: .utf8) else { return nil }
        do {
            return try AES.GCM.seal(data, using: key).combined
        } catch {
            AppLogger.log("⚠️ [EncryptionService] Encryption failed: \(error)")
            return nil
        }
    }

    /// Decrypts ciphertext under the data key. Returns nil for legacy
    /// PIN-encrypted content — use `decryptMigrating(_:legacyPIN:)` for that.
    func decrypt(_ ciphertext: Data) -> String? {
        guard let key = dataKey() else { return nil }
        return Self.open(ciphertext, using: key)
    }

    /// Encrypts raw bytes under the data key — the `Data` sibling of
    /// `encrypt(_ plaintext: String)`, for content that isn't text (photos).
    /// No legacy/PIN variant needed: photos are a new-only feature shipping
    /// after the data-key migration, so no photo ciphertext can predate it.
    func encryptData(_ plaintext: Data) -> Data? {
        guard let key = dataKey() else { return nil }
        do {
            return try AES.GCM.seal(plaintext, using: key).combined
        } catch {
            AppLogger.log("⚠️ [EncryptionService] Data encryption failed: \(error)")
            return nil
        }
    }

    /// Decrypts raw bytes under the data key — the `Data` sibling of `decrypt(_:)`.
    func decryptData(_ ciphertext: Data) -> Data? {
        guard let key = dataKey() else { return nil }
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: ciphertext)
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            return nil
        }
    }

    /// Reads content written under either scheme.
    ///
    /// Tries the data key first, then falls back to the legacy PBKDF2(PIN) key.
    /// `needsRewrite` is true when the fallback succeeded, which is the signal
    /// for `EncryptionMigrator` to re-encrypt that entry under the data key.
    ///
    /// AES-GCM is authenticated, so a wrong key fails cleanly rather than
    /// returning plausible garbage — trying both is safe.
    func decryptMigrating(_ ciphertext: Data, legacyPIN: String?) -> (text: String, needsRewrite: Bool)? {
        if let text = decrypt(ciphertext) {
            return (text, false)
        }
        if let pin = legacyPIN, let text = decrypt(ciphertext, withPIN: pin) {
            return (text, true)
        }
        return nil
    }

    private static func open(_ ciphertext: Data, using key: SymmetricKey) -> String? {
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: ciphertext)
            return String(data: try AES.GCM.open(sealedBox, using: key), encoding: .utf8)
        } catch {
            return nil
        }
    }

    // MARK: - Legacy PIN Key Derivation (migration reads only)

    private let cacheLock = NSLock()
    /// The last successfully derived key, keyed by (PIN, salt). The salt is fixed
    /// per install, so for a given PIN the key is stable — caching it collapses
    /// the per-entry PBKDF2 (100k iterations) into one derivation per session,
    /// which is the dominant per-chat-message cost when decrypting every entry.
    private var derivedKeyCache: (pin: String, saltHash: Int, key: SymmetricKey)?
    /// Number of times the expensive PBKDF2 derivation actually ran (test hook).
    private(set) var pbkdf2DerivationCount = 0

    /// Clears the cached derived key. Call on PIN change / sign-out / delete-everything.
    func clearDerivedKeyCache() {
        cacheLock.lock(); derivedKeyCache = nil; cacheLock.unlock()
    }

    /// Derives a 256-bit encryption key from PIN using PBKDF2-SHA256 with stored salt
    /// Uses 100,000 iterations as recommended by OWASP for password-based key derivation.
    /// Cached per (PIN, salt) so repeated decrypts don't re-run PBKDF2.
    func deriveKey(from pin: String) -> SymmetricKey? {
        guard let salt = getOrCreateSalt(),
              let pinData = pin.data(using: .utf8) else {
            return nil
        }

        let saltHash = salt.hashValue
        cacheLock.lock()
        if let cached = derivedKeyCache, cached.pin == pin, cached.saltHash == saltHash {
            cacheLock.unlock()
            return cached.key
        }
        cacheLock.unlock()

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

        let key = SymmetricKey(data: derivedKeyData)
        cacheLock.lock()
        pbkdf2DerivationCount += 1
        derivedKeyCache = (pin, saltHash, key)
        cacheLock.unlock()
        return key
    }

    // MARK: - Encryption/Decryption

    /// Encrypts under the legacy PIN-derived key.
    ///
    /// **Do not use for new writes** — `encrypt(_:)` is the current path. This
    /// remains only so tests can build legacy fixtures for the migration.
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

    /// Decrypts legacy PIN-encrypted content. **Migration reads only** — new
    /// content is written under the data key. Called speculatively by
    /// `decryptMigrating(_:legacyPIN:)`, so failure is expected and not logged.
    func decrypt(_ ciphertext: Data, withPIN pin: String) -> String? {
        guard let key = deriveKey(from: pin) else { return nil }
        return Self.open(ciphertext, using: key)
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

    /// Deletes the legacy encryption salt from Keychain.
    func deleteSalt() {
        keychain.delete(forAccount: saltKeychainKey)
        clearDerivedKeyCache()   // the salt changed → any cached key is stale
    }

    /// Destroys **all** key material: the data key and the legacy salt.
    ///
    /// This makes every existing entry permanently unreadable, which is the
    /// point — it backs Delete Everything. It must NOT be called on a PIN
    /// change: the PIN no longer has anything to do with the data key, and
    /// wiping the key here would destroy the user's journal.
    func clearAll() {
        keychain.delete(forAccount: dataKeyKeychainKey)
        dataKeyLock.lock(); cachedDataKey = nil; dataKeyLock.unlock()
        deleteSalt()
    }
}
