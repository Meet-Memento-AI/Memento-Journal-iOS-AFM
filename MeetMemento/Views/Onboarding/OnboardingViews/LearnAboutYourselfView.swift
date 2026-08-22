//
//  LearnAboutYourselfView.swift
//  MeetMemento
//
//  Onboarding step: journal goals (Figma 334:1600).
//

import SwiftUI

public struct LearnAboutYourselfView: View {
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @EnvironmentObject var onboardingViewModel: OnboardingViewModel

    @State private var entryText: String = ""
    @FocusState private var isFocused: Bool

    public var onComplete: ((String) -> Void)?
    public var isFirstStep: Bool = false
    public var onBack: (() -> Void)?

    /// Figma well height (334:1600).
    private let editorMinHeight: CGFloat = 200

    public init(onComplete: ((String) -> Void)? = nil, isFirstStep: Bool = false, onBack: (() -> Void)? = nil) {
        self.onComplete = onComplete
        self.isFirstStep = isFirstStep
        self.onBack = onBack
    }

    public var body: some View {
        OnboardingPageScaffold(
            onBack: onBack,
            scrolls: true
        ) {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                titleSection
                bodyField
            }
        } footer: {
            PrimaryButton(
                title: "Next step",
                systemImage: "arrow.right",
                imagePlacement: .trailing
            ) {
                completeStep()
            }
            .accessibilityLabel("Continue")
            .accessibilityHint("Double-tap to save and continue")
            .accessibilityIdentifier("onboarding.continueLearn")
        }
        .onAppear {
            if entryText.isEmpty, !onboardingViewModel.personalizationText.isEmpty {
                entryText = onboardingViewModel.personalizationText
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                isFocused = true
            }
        }
    }

    // MARK: - Subviews

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text("What are your journal goals?")
                .font(type.h3)
                .foregroundStyle(theme.foreground)

            Text("This will help customize your experience.")
                .font(type.body1Medium)
                .foregroundStyle(theme.mutedForeground)
        }
    }

    private var bodyField: some View {
        ZStack(alignment: .topLeading) {
            if entryText.isEmpty {
                Text("Start writing here...")
                    .font(type.inputLarge)
                    .foregroundStyle(GrayScale.gray400)
                    .padding(Spacing.md)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $entryText)
                .font(type.inputLarge)
                .lineSpacing(type.bodyLineSpacing(for: 18))
                .foregroundStyle(theme.foreground)
                .focused($isFocused)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, Spacing.xxs)
                .accessibilityLabel("Journal goals")
                .accessibilityIdentifier("onboarding.journalGoals")
        }
        .frame(minHeight: editorMinHeight, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: theme.radius.button, style: .continuous)
                .fill(theme.cardBackground)
        )
        .clipShape(RoundedRectangle(cornerRadius: theme.radius.button, style: .continuous))
    }

    // MARK: - Actions

    private func completeStep() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let trimmedText = entryText.trimmingCharacters(in: .whitespacesAndNewlines)
        onComplete?(trimmedText)
    }
}

// MARK: - Previews

#Preview("Light") {
    LearnAboutYourselfView()
        .useTheme()
        .useTypography()
        .environmentObject(OnboardingViewModel())
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    LearnAboutYourselfView()
        .useTheme()
        .useTypography()
        .environmentObject(OnboardingViewModel())
        .preferredColorScheme(.dark)
}

#Preview("With Content") {
    LearnAboutYourselfView()
        .useTheme()
        .useTypography()
        .environmentObject(OnboardingViewModel())
}
