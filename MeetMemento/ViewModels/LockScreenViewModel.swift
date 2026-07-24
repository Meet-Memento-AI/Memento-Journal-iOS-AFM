//
//  LockScreenViewModel.swift
//  MeetMemento
//
//  Manages app lock/unlock state separate from authentication state.
//

import Foundation
import SwiftUI

/// Notification posted when the app is unlocked with PIN (for encryption operations)
extension Notification.Name {
    static let didUnlockWithPIN = Notification.Name("didUnlockWithPIN")
}

@MainActor
class LockScreenViewModel: ObservableObject {
    @Published var isLocked: Bool = true
    @Published var isAuthenticating: Bool = false
    @Published var showPINFallback: Bool = false
    @Published var biometricFailureCount: Int = 0

    /// Flag to skip lock screen immediately after onboarding completion
    @Published var skipNextLockScreen: Bool = false

    private let securityService = SecurityService.shared

    /// Call this before checking `shouldShowLockScreen` to handle the skip-after-onboarding case.
    /// This consumes the `skipNextLockScreen` flag and unlocks if needed.
    func consumeSkipNextLockScreen() {
        if skipNextLockScreen {
            skipNextLockScreen = false
            isLocked = false
        }
    }

    /// Whether the lock screen should be shown based on security mode and lock state.
    /// Note: Call `consumeSkipNextLockScreen()` before accessing this property.
    var shouldShowLockScreen: Bool {
        guard hasSecuritySetup else { return false }
        return isLocked
    }

    /// Whether security is set up (either FaceID or PIN).
    var hasSecuritySetup: Bool {
        securityService.currentMode != .none
    }

    /// Whether PIN fallback is available (PIN is set up).
    var hasPINFallback: Bool {
        securityService.getPIN() != nil
    }

    /// The stored PIN, if any — used to hand off encryption key material on
    /// successful unlock via any method (biometric, PIN entry, or device
    /// passcode fallback). Not displayed to the user.
    var currentPIN: String? {
        securityService.getPIN()
    }

    /// The biometric type name for display ("Face ID", "Touch ID", etc.).
    var biometricTypeName: String {
        securityService.biometricType ?? "Face ID"
    }

    /// Whether biometric authentication is available on this device.
    var isBiometricAvailable: Bool {
        securityService.isBiometricAvailable
    }

    /// The current security mode.
    var currentSecurityMode: SecurityService.SecurityMode {
        securityService.currentMode
    }

    // MARK: - Authentication

    /// Triggers biometric authentication (Face ID / Touch ID).
    func authenticateWithBiometrics() async {
        guard !isAuthenticating else { return }

        isAuthenticating = true

        let success = await securityService.authenticateWithBiometrics(
            reason: "Unlock Memento"
        )

        isAuthenticating = false

        if success {
            // After biometric success, retrieve PIN from Keychain for encryption
            if let storedPIN = securityService.getPIN() {
                NotificationCenter.default.post(
                    name: .didUnlockWithPIN,
                    object: nil,
                    userInfo: ["pin": storedPIN]
                )
            }
            unlock()
        } else {
            biometricFailureCount += 1
            // After 3 failures, automatically show PIN fallback if available
            if biometricFailureCount >= 3 && hasPINFallback {
                showPINFallback = true
            }
        }
    }

    /// Validates the entered PIN and posts notification on success for encryption operations.
    func validatePIN(_ pin: String) -> Bool {
        let isValid = securityService.validatePIN(pin)
        if isValid {
            // Post notification with PIN for encryption operations
            NotificationCenter.default.post(
                name: .didUnlockWithPIN,
                object: nil,
                userInfo: ["pin": pin]
            )
            unlock()
        }
        return isValid
    }

    /// Unlocks the app.
    func unlock() {
        isLocked = false
        showPINFallback = false
        biometricFailureCount = 0
    }

    /// Locks the app (called when app backgrounds).
    func lock() {
        guard securityService.currentMode != .none else { return }
        isLocked = true
        showPINFallback = false
        biometricFailureCount = 0  // Reset for clean state on return
    }

    /// Switches to PIN fallback mode.
    func switchToPINFallback() {
        showPINFallback = true
    }

    /// Switches back to biometric mode.
    func switchToBiometric() {
        showPINFallback = false
    }
}
