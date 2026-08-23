//
//  EditJournalGoalsView.swift
//  MeetMemento
//
//  Settings editor for ThemeCatalog themes. Chrome matches
//  ThemeConfirmationView; persist + lens rebuild stay Settings-only.
//

import SwiftUI

public struct EditJournalGoalsView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    @State private var selectedIds: Set<String> = Set(
        LocalProfileStore.ensureMigratedProfile().confirmedThemeIds
    )
    @State private var isSaving = false

    public init() {}

    public var body: some View {
        OnboardingPageScaffold(
            onBack: { dismiss() },
            scrolls: true
        ) {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                titleSection

                ForEach(ThemeFamily.allCases) { family in
                    let themes = ThemeCatalog.themes(in: family)
                    if !themes.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            sectionLabel(family.title)
                            themeChipFlow(themes)
                        }
                    }
                }
            }
        } footer: {
            PrimaryButton(title: "Save", isLoading: isSaving) {
                saveChanges()
            }
            .opacity(canSave ? 1.0 : 0.5)
            .disabled(!canSave || isSaving)
            .accessibilityIdentifier("settings.saveThemes")
        }
    }

    // MARK: - Subviews

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: OnboardingLayout.fieldSpacing) {
            Text("Fine-tune your journal themes")
                .font(type.h4)
                .foregroundStyle(theme.foreground)

            Text("You can change this anytime")
                .font(type.body1Medium)
                .foregroundStyle(theme.mutedForeground)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(type.body1Medium)
            .foregroundStyle(theme.foreground)
    }

    private func themeChipFlow(_ themes: [JournalTheme]) -> some View {
        ThemeFlowLayout(spacing: Spacing.xs) {
            ForEach(themes) { themeItem in
                SelectableThemeTag(
                    text: themeItem.displayName,
                    isSelected: selectedIds.contains(themeItem.id),
                    onTap: { toggle(themeItem.id) }
                )
                .accessibilityIdentifier("settings.theme.\(themeItem.id)")
            }
        }
    }

    private var canSave: Bool {
        !selectedIds.isEmpty && selectedIds.count <= ThemeCatalog.maxConfirmedThemes
    }

    private func toggle(_ id: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if selectedIds.contains(id) {
                selectedIds.remove(id)
            } else if selectedIds.count < ThemeCatalog.maxConfirmedThemes {
                selectedIds.insert(id)
            }
        }
    }

    private func saveChanges() {
        guard canSave else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isSaving = true
        Task {
            do {
                _ = try await ExperienceProfileBuilder.rebuildLensPreservingThemes(
                    confirmedThemeIds: Array(selectedIds),
                    reflection: LocalProfileStore.personalizationText
                )
                await MainActor.run {
                    isSaving = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
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
}

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
