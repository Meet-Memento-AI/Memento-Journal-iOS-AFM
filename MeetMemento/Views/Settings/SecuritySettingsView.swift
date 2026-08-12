//
//  SecuritySettingsView.swift
//  MeetMemento
//
//  Lets the user turn the app lock on or off, change their PIN, and switch
//  Face ID on or off — after onboarding, not only during it.
//
//  Why this exists: onboarding's skip dialog has always said "You can turn this
//  on later in Settings", and until now that was false. Every call site of
//  `setSecurityMode`/`savePIN` lived in `OnboardingCoordinatorView`, so a user
//  who skipped the lock could never protect their journal, and a user who set a
//  PIN could never change it — short of Delete Everything.
//
//  It was false for a structural reason, not an oversight: journal content used
//  to be encrypted with PBKDF2(PIN), so changing the PIN silently orphaned every
//  entry. `EncryptionService` now encrypts under a Keychain-resident data key
//  and the PIN is purely an access gate, which is what makes this screen safe.
//
//  The one remaining hazard is legacy content still sealed under the old
//  PIN-derived key. `ensureNoLegacyContent()` forces that migration to complete
//  BEFORE any PIN mutation — otherwise changing the PIN would strand exactly the
//  entries that had not been rewritten yet.
//

import SwiftUI

struct SecuritySettingsView: View {
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @EnvironmentObject private var entryViewModel: EntryViewModel

    @StateObject private var pinFlowViewModel = OnboardingViewModel()

    @State private var mode: SecurityService.SecurityMode = SecurityService.shared.currentMode
    @State private var pinFlow: PinFlow?
    @State private var showDisableConfirmation = false
    @State private var errorMessage: String?
    @State private var isWorking = false

    /// Which PIN-entry flow is on screen, and what to do with the result.
    private enum PinFlow: Identifiable {
        case enableWithPIN
        case enableWithFaceID
        case change
        var id: String {
            switch self {
            case .enableWithPIN: return "enable-pin"
            case .enableWithFaceID: return "enable-faceid"
            case .change: return "change"
            }
        }
        var isFaceIDBackup: Bool { self == .enableWithFaceID }
    }

    private var isLockOn: Bool { mode != .none }
    private var biometricName: String { SecurityService.shared.biometricType ?? "Face ID" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                lockSection
                if isLockOn { pinSection }
                explainer
                Spacer(minLength: Spacing.xxxl)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.xs)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("Security")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $pinFlow) { flow in
            NavigationStack {
                SetupPinView(isFaceIDBackup: flow.isFaceIDBackup) { pin in
                    pinFlowViewModel.confirmedPin = pin
                    completePinFlow(flow, pin: pin)
                } onCancel: {
                    pinFlow = nil
                }
                .environmentObject(pinFlowViewModel)
                .useTheme()
                .useTypography()
            }
        }
        .confirmationDialog(
            "Turn off the app lock?",
            isPresented: $showDisableConfirmation,
            titleVisibility: .visible
        ) {
            Button("Turn Off Lock", role: .destructive) { disableLock() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Anyone who can unlock this phone will be able to read your journal. Your entries stay encrypted on disk either way.")
        }
        .alert("Couldn't update security", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear { mode = SecurityService.shared.currentMode }
    }

    // MARK: - Sections

    private var lockSection: some View {
        SettingsSection(title: "App Lock") {
            SettingsToggleRow(
                icon: "lock.fill",
                title: "Require unlock",
                subtitle: isLockOn
                    ? "Memento asks for \(mode == .faceID ? biometricName : "your PIN") when you open it"
                    : "Memento opens without asking for anything",
                isOn: Binding(
                    get: { isLockOn },
                    set: { wantsOn in
                        if wantsOn { beginEnable() } else { showDisableConfirmation = true }
                    }
                ),
                accessibilityIdentifier: "security.lockToggle"
            )

            if isLockOn && SecurityService.shared.isBiometricAvailable {
                SettingsRowDivider()
                SettingsToggleRow(
                    icon: "faceid",
                    title: "Use \(biometricName)",
                    subtitle: "Unlock with \(biometricName), with your PIN as a fallback",
                    isOn: Binding(
                        get: { mode == .faceID },
                        set: { setBiometrics(enabled: $0) }
                    ),
                    accessibilityIdentifier: "security.biometricToggle"
                )
            }
        }
    }

    private var pinSection: some View {
        SettingsSection(title: "PIN") {
            SettingsRow(
                icon: "number",
                title: "Change PIN",
                subtitle: "Pick a new 4-digit PIN",
                showChevron: true,
                showProgress: isWorking,
                accessibilityIdentifier: "security.changePIN"
            ) {
                guard ensureNoLegacyContent() else { return }
                pinFlow = .change
            }
        }
    }

    private var explainer: some View {
        Text("Your journal is encrypted on this device whether or not the lock is on. The lock controls who can open Memento; it is not what keeps your entries private.")
            .font(type.body2)
            .foregroundStyle(theme.mutedForeground)
            .padding(.horizontal, Spacing.xxs)
    }

    // MARK: - Actions

    private func beginEnable() {
        guard ensureNoLegacyContent() else { return }
        pinFlow = SecurityService.shared.isBiometricAvailable ? .enableWithFaceID : .enableWithPIN
    }

    private func completePinFlow(_ flow: PinFlow, pin: String) {
        guard SecurityService.shared.savePIN(pin) else {
            errorMessage = "Your PIN could not be saved to the keychain. Please try again."
            pinFlow = nil
            return
        }
        let newMode: SecurityService.SecurityMode = flow.isFaceIDBackup ? .faceID : .pin
        // A change keeps whichever unlock method was already in use.
        SecurityService.shared.setSecurityMode(flow == .change ? mode : newMode)
        entryViewModel.setSessionPIN(pin)
        mode = SecurityService.shared.currentMode
        pinFlow = nil
    }

    private func setBiometrics(enabled: Bool) {
        // Both modes are backed by the same stored PIN, so this never touches
        // key material and cannot strand an entry.
        SecurityService.shared.setSecurityMode(enabled ? .faceID : .pin)
        mode = SecurityService.shared.currentMode
    }

    private func disableLock() {
        // Deliberately keeps the PIN in the keychain rather than deleting it —
        // it is still the only way to read any entry that has not yet been
        // migrated off the legacy key. `SecurityMode.none` is what stops the
        // lock screen appearing, exactly as the onboarding skip path does.
        SecurityService.shared.setSecurityMode(.none)
        mode = SecurityService.shared.currentMode
    }

    /// Forces any entry still encrypted under the legacy PBKDF2(PIN) key to be
    /// rewritten under the data key, and reports whether that succeeded.
    ///
    /// Changing or removing the PIN before this completes would permanently
    /// strand those entries. Returns false (and surfaces an error) rather than
    /// letting a PIN mutation proceed on an incompletely migrated store.
    @discardableResult
    private func ensureNoLegacyContent() -> Bool {
        isWorking = true
        defer { isWorking = false }

        let pin = SecurityService.shared.getPIN()
        // Reading with the PIN rewrites anything legacy it finds.
        let withPIN = JournalService.shared.loadAllEntriesLocally(legacyPIN: pin).count
        // Reading without it proves nothing depends on the PIN any more.
        let withoutPIN = JournalService.shared.loadAllEntriesLocally(legacyPIN: nil).count

        guard withPIN == withoutPIN else {
            AppLogger.log("⚠️ [SecuritySettings] \(withPIN - withoutPIN) entries still require the legacy PIN; blocking PIN mutation")
            errorMessage = "Some entries are still being upgraded. Please reopen your journal, then try again."
            return false
        }
        return true
    }
}
