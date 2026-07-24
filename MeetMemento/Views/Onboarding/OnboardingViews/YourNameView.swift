//
//  YourNameView.swift
//  MeetMemento
//
//  First onboarding screen - collects user's first and last name
//

import SwiftUI

public struct YourNameView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @EnvironmentObject var onboardingViewModel: OnboardingViewModel

    @State private var firstName: String = ""
    @State private var lastName: String = ""

    public var onComplete: (() -> Void)?
    public var isFirstStep: Bool = false
    public var onBack: (() -> Void)?

    public init(onComplete: (() -> Void)? = nil, isFirstStep: Bool = false, onBack: (() -> Void)? = nil) {
        self.onComplete = onComplete
        self.isFirstStep = isFirstStep
        self.onBack = onBack
    }

    public var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Custom header with back button
                headerSection

                // Content area
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Title section
                        titleSection
                            .padding(.top, 8)

                        // Input fields
                        inputFieldsSection
                            .padding(.top, 24)

                        Spacer(minLength: 120)
                    }
                    .padding(.horizontal, 20)
                }
            }

            // Continue button at bottom
            VStack {
                Spacer()
                PrimaryButton(title: "Continue") {
                    saveAndContinue()
                }
                .opacity(canContinue ? 1.0 : 0.5)
                .disabled(!canContinue)
                .padding(.horizontal, 16)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Subviews

    private var headerSection: some View {
        ZStack(alignment: .top) {
            // Background gradient
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: theme.background, location: 0),
                    .init(color: theme.background.opacity(0), location: 1)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
            .frame(height: 64)

            // Header content
            HStack(alignment: .center, spacing: 12) {
                // Back button
                IconButtonNav(
                    icon: "chevron.left",
                    iconSize: 20,
                    buttonSize: 40,
                    foregroundColor: theme.foreground,
                    useDarkBackground: false,
                    enableHaptic: true,
                    onTap: { onBack?() ?? dismiss() }
                )
                .accessibilityLabel("Back")

                Spacer()

                // Placeholder for alignment
                Color.clear
                    .frame(width: 40, height: 40)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What's your name")
                .font(type.h3)
                .foregroundStyle(theme.foreground)

            Text("We’d like to know more about you. This shouldn’t take more than 5 minutes.")
                .font(type.body1)
                .foregroundStyle(theme.mutedForeground)
        }
    }

    private var inputFieldsSection: some View {
        VStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                AppTextField(
                    placeholder: "First name",
                    text: $firstName,
                    textInputAutocapitalization: .words
                )
            }

            VStack(alignment: .leading, spacing: 8) {

                AppTextField(
                    placeholder: "Last name",
                    text: $lastName,
                    textInputAutocapitalization: .words
                )
            }
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
