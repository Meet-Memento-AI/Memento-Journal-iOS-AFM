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
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                titleSection
                inputFieldsSection
            }
        } footer: {
            PrimaryButton(
                title: "Next step",
                systemImage: "arrow.right",
                imagePlacement: .trailing
            ) {
                saveAndContinue()
            }
            .opacity(canContinue ? 1.0 : 0.5)
            .disabled(!canContinue)
            // Stable UI-test target: do not query by visible title —
            // iOS 27's keyboard swipe-to-type intro overlay has its own
            // Continue button, and this CTA copy is design-owned.
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
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text("Let’s get you started")
                .font(type.h3)
                .foregroundStyle(theme.foreground)

            Text("What should Memento call you?")
                .font(type.body1Medium)
                .foregroundStyle(theme.mutedForeground)
        }
    }

    private var inputFieldsSection: some View {
        VStack(spacing: Spacing.md) {
            AppTextField(
                placeholder: "First name",
                text: $firstName,
                textInputAutocapitalization: .words,
                label: "First name",
                isFilled: true
            )

            AppTextField(
                placeholder: "Last name",
                text: $lastName,
                textInputAutocapitalization: .words,
                label: "Last name",
                isFilled: true
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
