//
//  ConfirmPinView.swift
//
//  Onboarding screen for confirming the 4-digit PIN
//

import SwiftUI

public struct ConfirmPinView: View {
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var onboardingViewModel: OnboardingViewModel

    @State private var pin: String = ""
    @State private var showError: Bool = false
    @State private var shakeOffset: CGFloat = 0
    @State private var isValidating: Bool = false
    @FocusState private var isPinFieldFocused: Bool

    let originalPin: String

    /// Whether this PIN is being set as a backup for FaceID users
    public var isFaceIDBackup: Bool

    public var onComplete: (() -> Void)?
    public var onCancel: (() -> Void)?

    /// Title changes based on context
    private var titleText: String {
        isFaceIDBackup ? "Confirm Backup PIN" : "Confirm Your PIN"
    }

    public init(
        originalPin: String,
        isFaceIDBackup: Bool = false,
        onComplete: (() -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self.originalPin = originalPin
        self.isFaceIDBackup = isFaceIDBackup
        self.onComplete = onComplete
        self.onCancel = onCancel
    }

    public var body: some View {
        OnboardingPageScaffold(
            onBack: onCancel,
            scrolls: true,
            centersContent: false
        ) {
            VStack(spacing: OnboardingLayout.sectionSpacing) {
                Text(titleText)
                    .font(type.h3)
                    .foregroundStyle(theme.foreground)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                pinInputFields
                    .offset(x: shakeOffset)

                if showError {
                    Text("PINs don't match. Please try again.")
                        .font(type.body2)
                        .foregroundStyle(Color.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
        } footer: {
            PrimaryButton(title: "Confirm PIN") {
                handlePinComplete()
            }
            .opacity(pin.count == 4 ? 1.0 : 0.5)
            .disabled(pin.count != 4 || isValidating)
        }
        .overlay {
            // Hidden TextField for iOS keyboard
            TextField("", text: $pin)
                .keyboardType(.numberPad)
                .focused($isPinFieldFocused)
                .opacity(0)
                .frame(width: 0, height: 0)
                .onChange(of: pin) { oldValue, newValue in
                    // Filter to only allow digits and limit to 4
                    var filtered = newValue.filter { $0.isNumber }
                    if filtered.count > 4 {
                        filtered = String(filtered.prefix(4))
                    }

                    // Only update state if the value actually changed to avoid re-entrancy
                    if filtered != newValue {
                        pin = filtered
                        return
                    }

                    // Auto-validate when 4 digits are entered
                    // Use async to let the current state update complete first
                    if filtered.count == 4 && oldValue.count < 4 && !isValidating {
                        Task { @MainActor in
                            validatePin(filtered)
                        }
                    }
                }
        }
        .onAppear {
            DispatchQueue.main.async {
                isPinFieldFocused = true
            }
        }
    }

    // MARK: - Subviews

    private var pinInputFields: some View {
        HStack(spacing: 16) {
            ForEach(0..<4, id: \.self) { index in
                Button {
                    // Focus the hidden TextField to show keyboard
                    DispatchQueue.main.async {
                        isPinFieldFocused = true
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(colorScheme == .dark ? GrayScale.gray700 : GrayScale.gray200)
                        .frame(width: 60, height: 70)
                        .overlay(
                            Group {
                                if index < pin.count {
                                    Circle()
                                        .fill(theme.foreground)
                                        .frame(width: 16, height: 16)
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("PIN entry")
        .accessibilityValue("\(pin.count) of 4 digits entered")
        .accessibilityHint("Double-tap to enter your PIN")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            isPinFieldFocused = true
        }
    }

    // MARK: - Actions

    private func handlePinComplete() {
        guard pin.count == 4, !isValidating else { return }
        validatePin(pin)
    }

    private func validatePin(_ enteredPin: String) {
        guard !isValidating else { return }
        isValidating = true

        if enteredPin == originalPin {
            // PIN matches - success
            // Dismiss keyboard
            isPinFieldFocused = false

            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onboardingViewModel.confirmedPin = enteredPin
            onComplete?()
            // isValidating intentionally left true: onComplete navigates away from
            // this screen on success, so there's no further input to guard against.
        } else {
            // PIN doesn't match — clear immediately so the next attempt is never
            // silently swallowed. Previously this was cleared only at the end of
            // the shake animation (~400-500ms later) while the hidden TextField
            // stayed focused and bound to the stale wrong digits; the onChange
            // filter's `prefix(4)` then discarded every digit retyped during that
            // window. Mirrors LockScreenView.validatePIN()'s pattern, which
            // clears immediately and runs the shake as an independent Task.
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            showError = true
            shakeAnimation()
            pin = ""
            isValidating = false
        }
    }

    private func shakeAnimation() {
        Task { @MainActor in
            withAnimation(.default) {
                shakeOffset = 10
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
            withAnimation(.default) {
                shakeOffset = -10
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
            withAnimation(.default) {
                shakeOffset = 10
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
            withAnimation(.default) {
                shakeOffset = 0
            }
        }
    }
}

// MARK: - Previews

#Preview("Light") {
    ConfirmPinView(originalPin: "1234")
        .useTheme()
        .useTypography()
        .environmentObject(OnboardingViewModel())
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    ConfirmPinView(originalPin: "1234")
        .useTheme()
        .useTypography()
        .environmentObject(OnboardingViewModel())
        .preferredColorScheme(.dark)
}
