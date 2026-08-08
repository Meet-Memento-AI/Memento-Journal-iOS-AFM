//
//  YourGoalsView.swift
//  MeetMemento
//
//  Legacy onboarding goals screen. Onboarding now uses ThemeConfirmationView;
// this remains for previews and any residual references, backed by ThemeCatalog.
//

import SwiftUI

public struct YourGoalsView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @EnvironmentObject var onboardingViewModel: OnboardingViewModel

    @State private var selectedGoals: Set<String> = []

    public var onComplete: (() -> Void)?
    public var isFirstStep: Bool = false
    public var onBack: (() -> Void)?

    /// Small starter subset of the catalog for this legacy screen.
    private let goals = ["Awareness", "Emotion", "Regulation", "Stress", "Communication", "Nurture", "Honesty", "Compassion"]

    public init(onComplete: (() -> Void)? = nil, isFirstStep: Bool = false, onBack: (() -> Void)? = nil) {
        self.onComplete = onComplete
        self.isFirstStep = isFirstStep
        self.onBack = onBack
    }

    public var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                headerSection

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        titleSection
                            .padding(.top, 8)

                        LegacyGoalsFlowLayout(spacing: 12) {
                            ForEach(goals, id: \.self) { goal in
                                Chip(
                                    text: goal,
                                    isSelected: selectedGoals.contains(goal),
                                    onTap: { toggleGoal(goal) }
                                )
                            }
                        }
                        .padding(.top, 24)

                        Spacer(minLength: 120)
                    }
                    .padding(.horizontal, 20)
                }
            }

            VStack {
                Spacer()
                PrimaryButton(title: "Continue") {
                    saveAndContinue()
                }
                .opacity(canContinue ? 1.0 : 0.5)
                .disabled(!canContinue)
                .accessibilityIdentifier("onboarding.continueGoals")
                .padding(.horizontal, 16)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 12) {
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
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Now let's narrow down your journalling goals")
                .font(type.h3)
                .foregroundStyle(theme.foreground)

            Text("What themes would you like to go deeper on? You can change this anytime.")
                .font(type.body1)
                .lineSpacing(3.4)
                .foregroundStyle(theme.mutedForeground)
        }
    }

    private var canContinue: Bool { !selectedGoals.isEmpty }

    private func toggleGoal(_ goal: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if selectedGoals.contains(goal) {
            selectedGoals.remove(goal)
        } else {
            selectedGoals.insert(goal)
        }
    }

    private func saveAndContinue() {
        guard canContinue else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onboardingViewModel.selectedGoals = Array(selectedGoals)
        onComplete?()
    }
}

private struct LegacyGoalsFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        calculateLayout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = calculateLayout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func calculateLayout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            totalWidth = max(totalWidth, currentX - spacing)
            totalHeight = max(totalHeight, currentY + lineHeight)
        }
        return (CGSize(width: totalWidth, height: totalHeight), positions)
    }
}

#Preview("Light") {
    YourGoalsView()
        .useTheme()
        .useTypography()
        .environmentObject(OnboardingViewModel())
        .preferredColorScheme(.light)
}
