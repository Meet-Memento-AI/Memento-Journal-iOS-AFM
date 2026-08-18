//
//  EditJournalGoalsView.swift
//  MeetMemento
//
//  Post-onboarding editor for ThemeCatalog themes that shape the experience.
//

import SwiftUI

public struct EditJournalGoalsView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    @State private var selectedIds: Set<String> = []
    @State private var currentLens: String?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var isRebuilding = false
    @State private var rebuildError: String?

    public init() {}

    public var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                headerSection

                if isLoading {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: theme.foreground))
                    Spacer()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            titleSection
                                .padding(.top, 8)

                            tuningSummary
                                .padding(.top, 16)

                            ForEach(ThemeFamily.allCases) { family in
                                let themes = ThemeCatalog.themes(in: family)
                                if !themes.isEmpty {
                                    Text(family.title)
                                        .font(type.body2Bold)
                                        .foregroundStyle(theme.foreground)
                                        .padding(.top, 24)

                                    GoalsFlowLayout(spacing: 12) {
                                        ForEach(themes) { item in
                                            Chip(
                                                text: item.displayName,
                                                isSelected: selectedIds.contains(item.id),
                                                onTap: { toggle(item.id) }
                                            )
                                            .accessibilityIdentifier("settings.theme.\(item.id)")
                                        }
                                    }
                                    .padding(.top, 12)
                                }
                            }

                            rebuildButton
                                .padding(.top, 32)

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
            loadExistingThemes()
        }
        .alert("Couldn't rebuild", isPresented: .init(
            get: { rebuildError != nil },
            set: { if !$0 { rebuildError = nil } }
        )) {
            Button("OK") { rebuildError = nil }
        } message: {
            Text(rebuildError ?? "Please try again.")
        }
    }

    // MARK: - Subviews

    private var headerSection: some View {
        HStack(alignment: .center) {
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
            .disabled(!canSave || isSaving || isRebuilding)
            .accessibilityIdentifier("settings.saveThemes")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your journal themes")
                .font(type.h3)
                .foregroundStyle(theme.foreground)

            Text("Update the one-word themes that quietly shape your journaling experience. Choose up to \(ThemeCatalog.maxConfirmedThemes).")
                .font(type.body2)
                .lineSpacing(3)
                .foregroundStyle(theme.mutedForeground)
        }
    }

    private var tuningSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How Memento is tuned for you")
                .font(type.body2Bold)
                .foregroundStyle(theme.foreground)
            if let currentLens, !currentLens.isEmpty {
                Text(currentLens)
                    .font(type.body2)
                    .foregroundStyle(theme.mutedForeground)
                    .accessibilityIdentifier("settings.tuningLens")
            } else if !selectedIds.isEmpty {
                Text("Themes selected. Rebuild the lens to refresh how chat leans into them.")
                    .font(type.body2)
                    .foregroundStyle(theme.mutedForeground)
            } else {
                Text("Select themes to personalize your experience.")
                    .font(type.body2)
                    .foregroundStyle(theme.mutedForeground)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var rebuildButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            Task { await rebuildLens() }
        } label: {
            HStack {
                if isRebuilding {
                    ProgressView()
                        .tint(theme.foreground)
                }
                Text(isRebuilding ? "Rebuilding…" : "Rebuild lens")
                    .font(type.body2Bold)
                    .foregroundStyle(theme.foreground)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .disabled(!canSave || isRebuilding || isSaving)
        .accessibilityIdentifier("settings.rebuildLens")
    }

    private var canSave: Bool {
        !selectedIds.isEmpty && selectedIds.count <= ThemeCatalog.maxConfirmedThemes
    }

    private func toggle(_ id: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else if selectedIds.count < ThemeCatalog.maxConfirmedThemes {
            selectedIds.insert(id)
        }
    }

    private func loadExistingThemes() {
        let profile = LocalProfileStore.ensureMigratedProfile()
        selectedIds = Set(profile.confirmedThemeIds)
        currentLens = profile.promptLens
        isLoading = false
    }

    private func saveChanges() {
        guard canSave else { return }
        isSaving = true
        Task {
            do {
                let profile = try await ExperienceProfileBuilder.rebuildLensPreservingThemes(
                    confirmedThemeIds: Array(selectedIds),
                    reflection: LocalProfileStore.personalizationText
                )
                await MainActor.run {
                    currentLens = profile.promptLens
                    isSaving = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    // Still persist themes even if rebuild fails.
                    var profile = LocalProfileStore.experienceProfile ?? .empty
                    profile.confirmedThemeIds = ThemeCatalog.validate(Array(selectedIds))
                    profile.promptLens = ExperienceProfileBuilder.deterministicLens(
                        themes: Array(selectedIds)
                    )
                    profile.builtAt = Date()
                    LocalProfileStore.experienceProfile = profile
                    isSaving = false
                    dismiss()
                }
            }
        }
    }

    private func rebuildLens() async {
        guard canSave else { return }
        isRebuilding = true
        defer { isRebuilding = false }
        do {
            let profile = try await ExperienceProfileBuilder.rebuildLensPreservingThemes(
                confirmedThemeIds: Array(selectedIds),
                reflection: LocalProfileStore.personalizationText
            )
            currentLens = profile.promptLens
        } catch {
            rebuildError = error.localizedDescription
        }
    }
}

private struct GoalsFlowLayout: Layout {
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

#Preview("EditJournalGoalsView • Light") {
    NavigationStack {
        EditJournalGoalsView()
    }
    .useTheme()
    .useTypography()
    .preferredColorScheme(.light)
}
