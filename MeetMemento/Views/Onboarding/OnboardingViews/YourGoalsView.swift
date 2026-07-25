//
//  YourGoalsView.swift
//  MeetMemento
//
//  Onboarding screen for selecting journaling themes/goals
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

    private let goals = [
        "Self awareness",
        "Emotion mapping",
        "Calming control",
        "Stress relief",
        "Thoughtful responses",
        "Self-kindness",
        "Honesty",
        "Compassion"
    ]

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

                        // Goal chips in flow layout
                        FlowLayout(spacing: 12) {
                            ForEach(goals, id: \.self) { goal in
                                Chip(
                                    text: goal,
                                    isSelected: selectedGoals.contains(goal),
                                    onTap: {
                                        toggleGoal(goal)
                                    }
                                )
                            }
                        }
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
                .accessibilityIdentifier("onboarding.continueGoals")
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
                // Back button - always visible with liquid glass styling
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
            Text("Now let's narrow down your journalling goals")
                .font(type.h3)
                .foregroundStyle(theme.foreground)

            Text("What themes would you like to go deeper on? You can change this anytime.")
                .font(type.body1)
                .lineSpacing(3.4)
                .foregroundStyle(theme.mutedForeground)
        }
    }

    // MARK: - Computed Properties

    private var canContinue: Bool {
        !selectedGoals.isEmpty
    }

    // MARK: - Actions

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

        // Save to view model
        onboardingViewModel.selectedGoals = Array(selectedGoals)

        onComplete?()
    }
}

// MARK: - Flow Layout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = calculateLayout(proposal: proposal, subviews: subviews)
        return result.size
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
                // Move to next line
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

// MARK: - Previews

#Preview("Light") {
    YourGoalsView()
        .useTheme()
        .useTypography()
        .environmentObject(OnboardingViewModel())
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    YourGoalsView()
        .useTheme()
        .useTypography()
        .environmentObject(OnboardingViewModel())
        .preferredColorScheme(.dark)
}
