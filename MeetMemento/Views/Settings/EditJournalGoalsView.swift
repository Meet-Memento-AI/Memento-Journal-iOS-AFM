//
//  EditJournalGoalsView.swift
//  MeetMemento
//
//  Post-onboarding view for editing journal focus areas/goals.
//  Based on YourGoalsView but with pre-populated data and save functionality.
//

import SwiftUI

public struct EditJournalGoalsView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    @State private var selectedGoals: Set<String> = []
    @State private var isLoading = true
    @State private var isSaving = false

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

    public init() {}

    public var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Custom header with back button and save
                headerSection

                if isLoading {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: theme.primary))
                    Spacer()
                } else {
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
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            loadExistingGoals()
        }
    }

    // MARK: - Subviews

    private var headerSection: some View {
        HStack(alignment: .center) {
            // Back button
            IconButtonNav(
                icon: "chevron.left",
                iconSize: 20,
                buttonSize: 40,
                foregroundColor: theme.foreground,
                useDarkBackground: false,
                enableHaptic: true,
                onTap: { dismiss() }
            )
            .accessibilityLabel("Back")

            Spacer()

            // Save button
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                saveChanges()
            } label: {
                if isSaving {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: theme.primaryForeground))
                        .frame(width: 60, height: 40)
                        .background(theme.primary)
                        .clipShape(Capsule())
                } else {
                    Text("Save")
                        .font(type.body2Bold)
                        .foregroundStyle(canSave ? theme.primaryForeground : theme.mutedForeground)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(canSave ? theme.primary : theme.muted)
                        .clipShape(Capsule())
                }
            }
            .disabled(!canSave || isSaving)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your journal goals")
                .font(type.h3)
                .foregroundStyle(theme.foreground)

            Text("Update the themes you'd like to go deeper on in your journaling.")
                .font(.system(size: 15))
                .lineSpacing(3)
                .foregroundStyle(theme.mutedForeground)
        }
    }

    // MARK: - Computed Properties

    private var canSave: Bool {
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

    private func loadExistingGoals() {
        Task {
            do {
                if let profile = try await UserService.shared.getCurrentProfile() {
                    await MainActor.run {
                        // Parse selected_topics from profile if available
                        if let topics = profile.selectedTopics {
                            selectedGoals = Set(topics)
                        }
                        isLoading = false
                    }
                } else {
                    await MainActor.run {
                        isLoading = false
                    }
                }
            } catch {
                AppLogger.log("⚠️ Failed to load user profile: \(error)")
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }

    private func saveChanges() {
        guard !selectedGoals.isEmpty else { return }

        isSaving = true
        Task {
            do {
                try await UserService.shared.updateGoals(Array(selectedGoals))
                await MainActor.run {
                    isSaving = false
                    dismiss()
                }
            } catch {
                AppLogger.log("⚠️ Failed to save goals: \(error)")
                await MainActor.run {
                    isSaving = false
                }
            }
        }
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

#Preview("EditJournalGoalsView • Light") {
    NavigationStack {
        EditJournalGoalsView()
    }
    .useTheme()
    .useTypography()
    .preferredColorScheme(.light)
}

#Preview("EditJournalGoalsView • Dark") {
    NavigationStack {
        EditJournalGoalsView()
    }
    .useTheme()
    .useTypography()
    .preferredColorScheme(.dark)
}
