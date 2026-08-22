//
//  SetupPinView.swift
//
//  Onboarding screen for creating a 4-digit PIN
//

import SwiftUI

public struct SetupPinView: View {
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var onboardingViewModel: OnboardingViewModel

    @State private var pin: String = ""
    @State private var isSubmitting: Bool = false
    @FocusState private var isPinFieldFocused: Bool

    /// Whether this PIN is being set as a backup for FaceID users
    public var isFaceIDBackup: Bool
    public var onComplete: ((String) -> Void)?
    public var onCancel: (() -> Void)?

    /// Title changes based on context
    private var titleText: String {
        isFaceIDBackup ? "Create a Backup PIN" : "Create Your PIN"
    }

    /// Subtitle explaining purpose
    private var subtitleText: String {
        isFaceIDBackup
            ? "This PIN unlocks your app if Face ID fails and encrypts your journals locally."
            : "This PIN will protect and encrypt your private journals."
    }

    public init(
        isFaceIDBackup: Bool = false,
        onComplete: ((String) -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self.isFaceIDBackup = isFaceIDBackup
        self.onComplete = onComplete
        self.onCancel = onCancel
    }

    public var body: some View {
        OnboardingPageScaffold(
            onBack: onCancel,
            scrolls: false,
            centersContent: true
        ) {
            VStack(spacing: Spacing.xxl) {
                VStack(spacing: Spacing.xxs) {
                    Text(titleText)
                        .font(type.h3)
                        .foregroundStyle(theme.foreground)

                    Text(subtitleText)
                        .font(type.body1Medium)
                        .foregroundStyle(theme.mutedForeground)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

                pinInputFields
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } footer: {
            PrimaryButton(title: "Set PIN") {
                handlePinComplete()
            }
            .opacity(pin.count == 4 ? 1.0 : 0.5)
            .disabled(pin.count != 4 || isSubmitting)
        }
        .overlay {
            // Hidden TextField for iOS keyboard
            TextField("", text: $pin)
                .keyboardType(.numberPad)
                .focused($isPinFieldFocused)
                .opacity(0)
                .frame(width: 0, height: 0)
                .onChange(of: pin) { _, newValue in
                    // Filter to only allow digits and limit to 4
                    var filtered = newValue.filter { $0.isNumber }
                    if filtered.count > 4 {
                        filtered = String(filtered.prefix(4))
                    }

                    // Only update state if the value actually changed to avoid re-entrancy
                    if filtered != newValue {
                        pin = filtered
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
        HStack(spacing: Spacing.md) {
            ForEach(0..<4, id: \.self) { index in
                Button {
                    // Focus the hidden TextField to show keyboard
                    DispatchQueue.main.async {
                        isPinFieldFocused = true
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous)
                        .fill(colorScheme == .dark ? GrayScale.gray700 : GrayScale.gray200)
                        .frame(width: 64, height: 80)
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
        guard pin.count == 4, !isSubmitting else { return }
        isSubmitting = true

        // Dismiss keyboard
        isPinFieldFocused = false

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onboardingViewModel.setupPin = pin
        onComplete?(pin)
        // isSubmitting intentionally left true: onComplete navigates to
        // ConfirmPinView on success, so there's no further input on this
        // screen to guard against.
    }
}

// MARK: - Previews

#Preview("Light") {
    SetupPinView()
        .useTheme()
        .useTypography()
        .environmentObject(OnboardingViewModel())
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    SetupPinView()
        .useTheme()
        .useTypography()
        .environmentObject(OnboardingViewModel())
        .preferredColorScheme(.dark)
}
