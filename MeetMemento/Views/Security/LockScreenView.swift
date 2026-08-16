//
//  LockScreenView.swift
//  MeetMemento
//
//  Lock screen that protects app content with FaceID or PIN.
//  Designed to match the LaunchScreen for seamless transition.
//

import SwiftUI
import LocalAuthentication

@MainActor
struct LockScreenView: View {
    @ObservedObject var viewModel: LockScreenViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    // PIN entry state
    @State private var enteredPIN: String = ""
    @State private var showPINError: Bool = false
    @State private var shakeOffset: CGFloat = 0
    @FocusState private var isPinFieldFocused: Bool

    /// Computed property for retry button visibility - derived from ViewModel state
    private var shouldShowRetryButton: Bool {
        viewModel.biometricFailureCount > 0 && !viewModel.isAuthenticating
    }

    private let pinLength = 4

    var body: some View {
        ZStack {
            // Theme background — was hardcoded white "matching LaunchScreen",
            // which made the lock screen a blinding white panel in dark mode.
            // The launch storyboard is still white; the brief transition
            // mismatch in dark mode is preferable to a wrong steady state.
            theme.background
                .ignoresSafeArea()

            VStack {

                // App logo - half size of LaunchScreen
                Image("MeetMemento-AppIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 70, height: 64)
                    .padding(.bottom, 16)

                // PIN entry or retry button at bottom
                if viewModel.showPINFallback {
                    pinEntryContent
                        .padding(.bottom, 60)
                } else if shouldShowRetryButton {
                    retryButton
                        .padding(.bottom, 80)
                } else if !viewModel.isBiometricAvailable && !viewModel.hasPINFallback {
                    // Emergency fallback - no auth method available
                    emergencyFallbackView
                        .padding(.bottom, 60)
                }
            }

            // Hidden TextField for iOS keyboard (PIN mode only)
            if viewModel.showPINFallback {
                TextField("", text: $enteredPIN)
                    .keyboardType(.numberPad)
                    .focused($isPinFieldFocused)
                    .opacity(0)
                    .frame(width: 0, height: 0)
                    .onChange(of: enteredPIN) { oldValue, newValue in
                        // Filter to only allow digits
                        let filtered = newValue.filter { $0.isNumber }
                        if filtered != newValue {
                            enteredPIN = filtered
                            return
                        }

                        // Limit to 4 digits
                        if filtered.count > 4 {
                            enteredPIN = String(filtered.prefix(4))
                        } else {
                            enteredPIN = filtered
                        }

                        // Auto-validate when 4 digits entered
                        if enteredPIN.count == pinLength {
                            validatePIN()
                        }
                    }
            }
        }
        .onAppear {
            // Reset local state for clean appearance
            enteredPIN = ""
            showPINError = false
            shakeOffset = 0
        }
        .task(id: viewModel.isLocked) {
            // Auto-trigger biometric auth when lock state changes to locked
            guard viewModel.isLocked else { return }

            // If biometrics not available, show PIN fallback immediately
            guard viewModel.isBiometricAvailable else {
                if viewModel.hasPINFallback {
                    viewModel.showPINFallback = true
                }
                return
            }

            guard !viewModel.showPINFallback else { return }
            try? await Task.sleep(nanoseconds: 300_000_000)
            await viewModel.authenticateWithBiometrics()
        }
        .onChange(of: viewModel.showPINFallback) { _, showPIN in
            // Auto-focus PIN field when switching to PIN mode
            if showPIN {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    isPinFieldFocused = true
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            guard viewModel.isLocked else { return }
            guard viewModel.isBiometricAvailable else { return }
            guard !viewModel.showPINFallback else { return }
            guard !viewModel.isAuthenticating else { return }

            Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard viewModel.isLocked && !viewModel.showPINFallback && !viewModel.isAuthenticating else { return }
                await viewModel.authenticateWithBiometrics()
            }
        }
    }

    // MARK: - Retry Button

    private var retryButton: some View {
        VStack(spacing: 16) {
            Button {
                Task {
                    await viewModel.authenticateWithBiometrics()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: biometricIconName)
                        .font(.system(size: 20)) // icon-size: not user text
                    Text("Try Again")
                        .font(type.body1)
                }
                .foregroundStyle(theme.primary)
                .padding(.vertical, 14)
                .padding(.horizontal, 28)
                .background(
                    Capsule()
                        .fill(theme.primary.opacity(0.1))
                )
            }

            // PIN fallback
            if viewModel.hasPINFallback {
                Button {
                    viewModel.switchToPINFallback()
                } label: {
                    Text("Use PIN")
                        .font(type.body2)
                        .foregroundStyle(theme.mutedForeground)
                }
            }
        }
    }

    // MARK: - Emergency Fallback View

    /// No accounts (spec 023 R6) — there is no sign-out escape hatch anymore.
    /// When biometrics and the app PIN both fail, the device passcode is the
    /// fallback: `.deviceOwnerAuthentication` (vs.
    /// `.deviceOwnerAuthenticationWithBiometrics`) falls back to the device's
    /// own passcode, which is already the root of trust for the
    /// Keychain-stored encryption salt, so this adds no new trust surface.
    private var emergencyFallbackView: some View {
        VStack(spacing: 16) {
            Text("Unable to authenticate")
                .font(type.body1)
                .foregroundStyle(theme.foreground)
            Text("Use your device passcode to unlock Memento")
                .font(type.body2)
                .foregroundStyle(theme.mutedForeground)
            Button {
                Task {
                    await authenticateWithDevicePasscode()
                }
            } label: {
                Text("Use Device Passcode")
                    .font(type.body1)
                    .foregroundStyle(.white)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 28)
                    .background(
                        Capsule()
                            .fill(theme.primary)
                    )
            }
        }
    }

    private func authenticateWithDevicePasscode() async {
        let context = LAContext()
        let success = (try? await context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Unlock Memento"
        )) ?? false

        if success {
            // Same encryption-key handoff as biometric/PIN unlock.
            if let storedPIN = viewModel.currentPIN {
                NotificationCenter.default.post(
                    name: .didUnlockWithPIN,
                    object: nil,
                    userInfo: ["pin": storedPIN]
                )
            }
            viewModel.unlock()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    // MARK: - PIN Entry Content

    private var pinEntryContent: some View {
        VStack(spacing: 24) {
            // PIN input fields (tappable to show keyboard)
            pinInputFields
                .offset(x: shakeOffset)

            // Error message
            if showPINError {
                Text("Incorrect PIN")
                    .font(type.body2)
                    .foregroundStyle(Color.red)
            }

            // Biometric fallback
            if viewModel.isBiometricAvailable {
                Button {
                    isPinFieldFocused = false
                    viewModel.switchToBiometric()
                    enteredPIN = ""
                    showPINError = false
                    Task {
                        await viewModel.authenticateWithBiometrics()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: biometricIconName)
                            .font(.system(size: 16)) // icon-size: not user text
                        Text("Use \(viewModel.biometricTypeName)")
                            .font(type.body2)
                    }
                    .foregroundStyle(theme.mutedForeground)
                }
                .padding(.top, 8)
            }

            // Forgot PIN (spec 023 R6): device passcode is always reachable,
            // even when a PIN exists but is forgotten — not just when no PIN
            // was ever set up (that case is emergencyFallbackView).
            Button {
                isPinFieldFocused = false
                Task {
                    await authenticateWithDevicePasscode()
                }
            } label: {
                Text("Forgot PIN? Use device passcode")
                    .font(type.body2)
                    .foregroundStyle(theme.mutedForeground)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - PIN Input Fields

    private var pinInputFields: some View {
        HStack(spacing: 16) {
            ForEach(0..<pinLength, id: \.self) { index in
                Button {
                    // Focus the hidden TextField to show keyboard
                    isPinFieldFocused = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(GrayScale.gray200)
                        // AX5: minHeight lets the box grow instead of overlapping
                        // neighbors when the digit (type.h2) scales up at large
                        // Dynamic Type sizes.
                        .frame(minWidth: 60, maxWidth: 60, minHeight: 70)
                        .overlay(
                            Group {
                                if index < enteredPIN.count {
                                    Text(String(enteredPIN[enteredPIN.index(enteredPIN.startIndex, offsetBy: index)]))
                                        // Deliberately NOT `type.h2`: h1/h2 are
                                        // the serif display face now, and Lora
                                        // numerals in a fixed 60pt PIN cell read
                                        // as a different control entirely. Same
                                        // size as h2 so the boxes are unchanged.
                                        .font(.custom("Manrope-Bold", size: Typography.baseSize3XL, relativeTo: .title))
                                        .foregroundStyle(theme.foreground)
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("PIN digit \(index + 1) of \(pinLength)")
                .accessibilityHint(index < enteredPIN.count ? "Filled" : "Empty")
            }
        }
    }

    // MARK: - PIN Validation

    private func validatePIN() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            if viewModel.validatePIN(enteredPIN) {
                // Success - viewModel will unlock
                isPinFieldFocused = false
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else {
                // Error - shake and reset
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                showPINError = true
                shakeAnimation()
                enteredPIN = ""
            }
        }
    }

    private func shakeAnimation() {
        Task { @MainActor in
            withAnimation(.interpolatingSpring(stiffness: 600, damping: 10)) {
                shakeOffset = 10
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
            withAnimation(.interpolatingSpring(stiffness: 600, damping: 10)) {
                shakeOffset = -10
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
            withAnimation(.interpolatingSpring(stiffness: 600, damping: 10)) {
                shakeOffset = 0
            }
        }
    }

    // MARK: - Helpers

    private var biometricIconName: String {
        switch viewModel.biometricTypeName {
        case "Touch ID":
            return "touchid"
        case "Optic ID":
            return "opticid"
        default:
            return "faceid"
        }
    }
}

// MARK: - Previews

#Preview("Face ID Mode") {
    LockScreenView(viewModel: LockScreenViewModel())
        .useTheme()
        .useTypography()
}

#Preview("PIN Mode") {
    let viewModel = LockScreenViewModel()
    viewModel.showPINFallback = true
    return LockScreenView(viewModel: viewModel)
        .useTheme()
        .useTypography()
}
