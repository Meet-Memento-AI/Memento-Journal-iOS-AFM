//
//  YourNameView.swift
//  MeetMemento
//
//  First onboarding screen - collects user's first and last name
//

import SwiftUI

public struct YourNameView: View {
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @EnvironmentObject var onboardingViewModel: OnboardingViewModel

    @State private var firstName: String = ""
    @State private var lastName: String = ""
    /// Dissolves in after Welcome's white handoff; opaque for step-slide appearances.
    @State private var contentOpacity: Double

    public var onComplete: (() -> Void)?
    public var isFirstStep: Bool = false
    public var onBack: (() -> Void)?
    /// Welcome → YourName white dissolve only. Off when this screen is shown via step slides.
    public var dissolvesInOnAppear: Bool = true

    public init(
        onComplete: (() -> Void)? = nil,
        isFirstStep: Bool = false,
        onBack: (() -> Void)? = nil,
        dissolvesInOnAppear: Bool = true
    ) {
        self.onComplete = onComplete
        self.isFirstStep = isFirstStep
        self.onBack = onBack
        self.dissolvesInOnAppear = dissolvesInOnAppear
        _contentOpacity = State(initialValue: dissolvesInOnAppear ? 0 : 1)
    }

    public var body: some View {
        OnboardingPageScaffold(
            onBack: onBack,
            scrolls: true
        ) {
            VStack(alignment: .leading, spacing: OnboardingLayout.sectionSpacing) {
                titleSection
                inputFieldsSection
            }
        } footer: {
            PrimaryButton(title: "Continue") {
                saveAndContinue()
            }
            .opacity(canContinue ? 1.0 : 0.5)
            .disabled(!canContinue)
            // Stable UI-test target: label-based queries ("Continue")
            // collide with iOS 27's keyboard swipe-to-type intro overlay,
            // which has its own Continue button.
            .accessibilityIdentifier("onboarding.continueName")
        }
        .opacity(contentOpacity)
        .onAppear {
            guard dissolvesInOnAppear else {
                contentOpacity = 1
                return
            }
            // Reset so back → Welcome → Get Started can replay the dissolve.
            contentOpacity = 0
            withAnimation(.easeInOut(duration: 0.55)) {
                contentOpacity = 1
            }
        }
    }

    // MARK: - Subviews

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: OnboardingLayout.titleBodySpacing) {
            Text("What's your name")
                .font(type.h3)
                .foregroundStyle(theme.foreground)

            Text("We’d like to know more about you. This shouldn’t take more than 5 minutes.")
                .font(type.body1)
                .foregroundStyle(theme.mutedForeground)
        }
    }

    private var inputFieldsSection: some View {
        VStack(spacing: OnboardingLayout.fieldSpacing) {
            AppTextField(
                placeholder: "First name",
                text: $firstName,
                textInputAutocapitalization: .words
            )

            AppTextField(
                placeholder: "Last name",
                text: $lastName,
                textInputAutocapitalization: .words
            )
        }
    }

    // MARK: - Computed Properties

    private var canContinue: Bool {
        !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Actions

    private func saveAndContinue() {
        guard canContinue else { return }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Save to view model
        onboardingViewModel.firstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        onboardingViewModel.lastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines)

        onComplete?()
    }
}

// MARK: - Previews

#Preview("Light") {
    YourNameView()
        .useTheme()
        .useTypography()
        .environmentObject(OnboardingViewModel())
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    YourNameView()
        .useTheme()
        .useTypography()
        .environmentObject(OnboardingViewModel())
        .preferredColorScheme(.dark)
}
