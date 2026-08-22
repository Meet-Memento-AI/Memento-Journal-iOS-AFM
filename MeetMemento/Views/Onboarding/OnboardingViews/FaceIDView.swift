//
//  FaceIDView.swift
//  MeetMemento
//
//  Onboarding screen for biometric authentication setup (Figma 617:3655).
//

import SwiftUI

public struct FaceIDView: View {
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var onboardingViewModel: OnboardingViewModel

    @State private var isAuthenticating: Bool = false
    @State private var showError: Bool = false

    public var onUseFaceID: (() -> Void)?
    public var onCreatePIN: (() -> Void)?
    /// Skip lock setup entirely (spec 023 R3 — app lock defaults on but is
    /// skippable, per REQ-DATA-004). Shown with explicit friction so it's
    /// never the path of least resistance. Not in the Figma frame; kept as
    /// a tertiary control under the two designed CTAs.
    public var onSkip: (() -> Void)?
    public var isFirstStep: Bool = false
    public var onBack: (() -> Void)?

    @State private var showSkipConfirmation = false

    /// Figma face-id glyph frame inside the copper well.
    private let iconSize: CGFloat = 64

    public init(
        onUseFaceID: (() -> Void)? = nil,
        onCreatePIN: (() -> Void)? = nil,
        onSkip: (() -> Void)? = nil,
        isFirstStep: Bool = false,
        onBack: (() -> Void)? = nil
    ) {
        self.onUseFaceID = onUseFaceID
        self.onCreatePIN = onCreatePIN
        self.onSkip = onSkip
        self.isFirstStep = isFirstStep
        self.onBack = onBack
    }

    public var body: some View {
        OnboardingPageScaffold(
            onBack: onBack,
            scrolls: false,
            centersContent: true
        ) {
            VStack(spacing: Spacing.md) {
                iconWell

                VStack(spacing: Spacing.xxs) {
                    Text("Enable FaceID")
                        .font(type.h3)
                        .foregroundStyle(theme.foreground)

                    Text("Use Face ID to encrypt your journals")
                        .font(type.body1Medium)
                        .foregroundStyle(theme.mutedForeground)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        } footer: {
            VStack(spacing: Spacing.md) {
                if showError {
                    Text("Face ID authentication failed. Please try again or use a PIN.")
                        .font(type.body2)
                        .foregroundStyle(Color.red)
                        .multilineTextAlignment(.center)
                }

                if isAuthenticating {
                    ProgressView()
                        .tint(theme.foreground)
                        .frame(height: 48)
                } else {
                    PrimaryButton(title: "Use Face ID") {
                        handleUseFaceID()
                    }
                }

                SecondaryButton(title: "Create a PIN instead") {
                    handleCreatePIN()
                }

                if onSkip != nil {
                    Button {
                        showSkipConfirmation = true
                    } label: {
                        Text("Skip for now")
                            .font(type.body2)
                            .foregroundStyle(theme.mutedForeground)
                    }
                }
            }
        }
        .confirmationDialog(
            "Skip journal protection?",
            isPresented: $showSkipConfirmation,
            titleVisibility: .visible
        ) {
            Button("Skip", role: .destructive) {
                onSkip?()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your journal will open without protection — anyone with your phone unlocked can read it. You can turn this on later in Settings.")
        }
    }

    // MARK: - Icon

    private var iconWell: some View {
        Image(systemName: "faceid")
            .font(.system(size: 48, weight: .medium)) // icon-size: not user text
            .foregroundStyle(iconColor)
            .frame(width: iconSize, height: iconSize)
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: theme.radius.xxl, style: .continuous)
                    .fill(iconWellFill)
            )
            .accessibilityHidden(true)
    }

    /// Figma `brand-copper/50` (#f9f3ed) → `primary50`. Dark: cordovan well
    /// so the cream chip doesn't flash on a black canvas.
    private var iconWellFill: Color {
        colorScheme == .dark ? PrimaryScale.primary900 : PrimaryScale.primary50
    }

    /// Figma `brand/copper/600` → `brandOnText`. Dark: the light-mode accent.
    private var iconColor: Color {
        colorScheme == .dark ? BrandColors.brandDark : BrandColors.brandOnText
    }

    // MARK: - Actions

    private func handleUseFaceID() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        guard !isAuthenticating else { return }
        isAuthenticating = true
        showError = false

        Task {
            let success = await SecurityService.shared.authenticateWithBiometrics(
                reason: "Set up Face ID for Memento"
            )

            await MainActor.run {
                isAuthenticating = false

                if success {
                    onboardingViewModel.useFaceID = true
                    onUseFaceID?()
                } else {
                    showError = true
                }
            }
        }
    }

    private func handleCreatePIN() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onboardingViewModel.useFaceID = false
        onCreatePIN?()
    }
}

// MARK: - Previews

#Preview("Light") {
    FaceIDView()
        .useTheme()
        .useTypography()
        .environmentObject(OnboardingViewModel())
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    FaceIDView()
        .useTheme()
        .useTypography()
        .environmentObject(OnboardingViewModel())
        .preferredColorScheme(.dark)
}
