//
//  SecurityService.swift
//  MeetMemento
//
//  Keychain PIN storage and Face ID / Touch ID biometric authentication.
//

import Foundation
import LocalAuthentication
import Security

class SecurityService {
    static let shared = SecurityService()

    private let keychain: KeychainStoring
    private let now: () -> Date
    private let pinKeychainKey = "com.sebastianmendo.MeetMemento.userPIN"
    private let securityModeKey = "com.sebastianmendo.MeetMemento.securityMode"
    private let lastActivityKey = "com.sebastianmendo.MeetMemento.lastActivityTimestamp"
    private let inactivityTimeoutDays: Double = 14

    /// `keychain` and `now` default to real implementations; tests inject a
    /// mock keychain (no Keychain entitlements in unit tests) and a fixed
    /// clock (so the 14-day auto-logout window is deterministic to test).
    init(keychain: KeychainStoring = SystemKeychainStore(), now: @escaping () -> Date = Date.init) {
        self.keychain = keychain
        self.now = now
    }

    enum SecurityMode: String {
        case faceID
        case pin
        case none
    }

    // MARK: - Activity Tracking

    /// Returns the last recorded activity timestamp, or nil if never set.
    var lastActivityTimestamp: Date? {
        get {
            guard let timestamp = UserDefaults.standard.object(forKey: lastActivityKey) as? Date else {
                return nil
            }
            return timestamp
        }
        set {
            UserDefaults.standard.set(newValue, forKey: lastActivityKey)
        }
    }

    /// Updates the last activity timestamp to the current time.
    func updateActivityTimestamp() {
        lastActivityTimestamp = now()
    }

    /// Checks if the user should be auto-logged out due to inactivity (14+ days).
    func shouldAutoLogout() -> Bool {
        guard let lastActivity = lastActivityTimestamp else {
            // No previous activity recorded - user is new or data was cleared
            return false
        }

        let daysSinceActivity = now().timeIntervalSince(lastActivity) / (60 * 60 * 24)
        return daysSinceActivity >= inactivityTimeoutDays
    }

    /// Clears the activity timestamp (called on sign out).
    func clearActivityTimestamp() {
        UserDefaults.standard.removeObject(forKey: lastActivityKey)
    }

    // MARK: - Security Mode

    /// Returns the stored security mode preference.
    var currentMode: SecurityMode {
        guard let raw = UserDefaults.standard.string(forKey: securityModeKey) else {
            return .none
        }
        return SecurityMode(rawValue: raw) ?? .none
    }

    func setSecurityMode(_ mode: SecurityMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: securityModeKey)
    }

    // MARK: - Biometric Authentication

    /// Checks if biometric authentication (Face ID / Touch ID) is available.
    var isBiometricAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// The type of biometric available ("Face ID", "Touch ID", or nil).
    var biometricType: String? {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return nil
        }
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return nil
        }
    }

    /// Authenticates the user with biometrics. Returns true on success.
    func authenticateWithBiometrics(reason: String = "Unlock Memento") async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "Use PIN"

        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
        } catch {
            AppLogger.log("⚠️ [SecurityService] Biometric auth failed: \(error)")
            return false
        }
    }

    // MARK: - Keychain PIN Storage

    /// Saves a PIN to the Keychain. Overwrites any existing PIN.
    func savePIN(_ pin: String) -> Bool {
        keychain.save(Data(pin.utf8), forAccount: pinKeychainKey)
    }

    /// Retrieves the stored PIN from the Keychain. Returns nil if not set.
    func getPIN() -> String? {
        guard let data = keychain.data(forAccount: pinKeychainKey) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Validates a PIN against the stored value using constant-time comparison
    /// to prevent timing attacks.
    func validatePIN(_ pin: String) -> Bool {
        guard let stored = getPIN() else { return false }
        return constantTimeCompare(stored, pin)
    }

    /// Performs a constant-time string comparison to prevent timing attacks.
    /// Returns true only if both strings are equal in length and content.
    private func constantTimeCompare(_ a: String, _ b: String) -> Bool {
        let aBytes = Array(a.utf8)
        let bBytes = Array(b.utf8)

        // Length check must still happen, but we continue comparison
        // to avoid leaking length information through timing
        guard aBytes.count == bBytes.count else {
            // Still do a dummy comparison to maintain constant time
            var result: UInt8 = 1 // Start with non-zero to indicate failure
            for i in 0..<max(aBytes.count, bBytes.count) {
                let aVal = i < aBytes.count ? aBytes[i] : 0
                let bVal = i < bBytes.count ? bBytes[i] : 0
                result |= aVal ^ bVal
            }
            return false
        }

        // XOR all bytes and accumulate - runs in constant time
        var result: UInt8 = 0
        for i in 0..<aBytes.count {
            result |= aBytes[i] ^ bBytes[i]
        }

        return result == 0
    }

    /// Removes the stored PIN from the Keychain.
    func deletePIN() {
        keychain.delete(forAccount: pinKeychainKey)
    }

    /// Clears all security settings (PIN + mode + activity timestamp). Used on account deletion.
    func clearAll() {
        deletePIN()
        UserDefaults.standard.removeObject(forKey: securityModeKey)
        clearActivityTimestamp()
    }
}
