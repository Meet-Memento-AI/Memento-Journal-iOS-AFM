//
//  IdentifierMigration.swift
//  withMemento
//
//  One-way migration of Keychain accounts and UserDefaults keys off the
//  pre-rename `com.sebastianmendo.MeetMemento.*` namespace and onto
//  `com.sebmendo.withMementoAI.*`.
//
//  Why this exists: several persisted keys embedded the bundle ID as a string.
//  Renaming those constants without moving the stored values would silently
//  orphan them — and for `EncryptionService`'s data-encryption key that is not
//  a cosmetic loss, it makes every existing entry undecryptable forever.
//
//  Scope and limits. Keychain items survive a bundle-ID change only when both
//  builds are signed by the same team and share the
//  `$(AppIdentifierPrefix)com.sebmendo.withMementoAI` access group, because
//  items live in the access group rather than the app container. UserDefaults
//  does NOT survive a bundle-ID change: the new bundle ID gets a new container,
//  so `migrateDefaultsKey` only helps within one install lineage. Both are
//  written to be no-ops when there is nothing to move, which is the normal
//  case on a fresh install.
//

import Foundation

enum IdentifierMigration {

    /// Copies a Keychain item from `legacyAccount` to `account`, then removes
    /// the old one. No-ops when the legacy item is absent or when `account`
    /// already holds a value — the current value always wins, so a partially
    /// completed migration cannot clobber newer data on a later launch.
    static func migrateKeychainAccount(
        from legacyAccount: String,
        to account: String,
        using keychain: KeychainStoring
    ) {
        guard keychain.data(forAccount: account) == nil else {
            // Already migrated (or freshly written). Drop any stale leftover.
            keychain.delete(forAccount: legacyAccount)
            return
        }
        guard let legacyValue = keychain.data(forAccount: legacyAccount) else { return }

        guard keychain.save(legacyValue, forAccount: account) else {
            // Leave the legacy item in place; retry on the next launch rather
            // than deleting the only copy of something we failed to re-store.
            AppLogger.log("⚠️ [IdentifierMigration] Failed to move Keychain item \(legacyAccount) → \(account); keeping the legacy copy")
            return
        }

        keychain.delete(forAccount: legacyAccount)
        AppLogger.log("🔐 [IdentifierMigration] Migrated Keychain item \(legacyAccount) → \(account)")
    }

    /// Copies a UserDefaults value from `legacyKey` to `key`, then removes the
    /// old one. Same precedence rule as the Keychain variant: an existing
    /// current value is never overwritten.
    static func migrateDefaultsKey(
        from legacyKey: String,
        to key: String,
        defaults: UserDefaults = .standard
    ) {
        guard defaults.object(forKey: key) == nil else {
            defaults.removeObject(forKey: legacyKey)
            return
        }
        guard let legacyValue = defaults.object(forKey: legacyKey) else { return }

        defaults.set(legacyValue, forKey: key)
        defaults.removeObject(forKey: legacyKey)
        AppLogger.log("🔐 [IdentifierMigration] Migrated UserDefaults key \(legacyKey) → \(key)")
    }
}
