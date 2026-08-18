//
//  FaceIDView.swift
//  MeetMemento
//
//  Onboarding screen for biometric authentication setup
//

import SwiftUI

public struct FaceIDView: View {
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @EnvironmentObject var onboardingViewModel: OnboardingViewModel

    @State private var isAuthenticating: Bool = false
    @State private var showError: Bool = false

    public var onUseFaceID: (() -> Void)?
    public var onCreatePIN: (() -> Void)?
    /// Skip lock setup entirely (spec 023 R3 — app lock defaults on but is
    /// skippable, per REQ-DATA-004). Shown with explicit friction so it's
    /// never the path of least resistance.
    public var onSkip: (() -> Void)?
    public var isFirstStep: Bool = false
    public var onBack: (() -> Void)?

    @State private var showSkipConfirmation = false

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
            VStack(spacing: OnboardingLayout.sectionSpacing) {
                Image(systemName: "faceid")
                    .font(.system(size: 80, weight: .thin)) // icon-size: not user text
                    .foregroundStyle(theme.foreground)
                    .accessibilityHidden(true)

                Text("Set up Face ID")
                    .font(type.h3)
                    .foregroundStyle(theme.foreground)
                    .multilineTextAlignment(.center)

                Text("You can use Face ID to encrypt your journals so you won't need to type in your PIN every time.")
                    .font(type.body1)
                    .lineSpacing(3.4)
                    .foregroundStyle(theme.mutedForeground)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } footer: {
            VStack(spacing: OnboardingLayout.footerStackSpacing) {
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
                    .padding(.top, 4)
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
