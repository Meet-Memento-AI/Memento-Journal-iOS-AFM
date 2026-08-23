//
//  ThemeConfirmationView.swift
//  MeetMemento
//
//  Onboarding step: AFM (or keyword fallback) suggests ThemeCatalog themes
//  from the LearnAboutYourself reflection; user confirms/edits before continue.
//

import SwiftUI

/// What the theme step produced, including the provenance of the estimate.
///
/// A struct rather than more positional callback arguments: `REQ-PRM-004` needs
/// the model and prompt version to travel with the lens, and six unlabelled
/// parameters at the call site is how the wrong one gets passed.
struct ThemeSelectionOutcome {
    let themeIds: [String]
    let promptLens: String?
    let suggestedIds: [String]
    /// Nil when the keyword fallback produced the suggestions — the fallback is
    /// not a model, and claiming one would misattribute the result.
    let modelIdentifier: String?
    let promptVersion: String?
}

public struct ThemeConfirmationView: View {
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @EnvironmentObject var onboardingViewModel: OnboardingViewModel

    var onComplete: ((ThemeSelectionOutcome) -> Void)?
    public var onBack: (() -> Void)?
    // Internal: `IntelligenceService` / `FoundationModelsIntelligenceService`
    // are app-internal types, so this can't be part of the public API.
    var intelligence: IntelligenceService

    @State private var selectedIds: Set<String> = []
    @State private var suggestedIds: [String] = []
    @State private var promptLens: String?
    @State private var estimateModelIdentifier: String?
    @State private var estimatePromptVersion: String?
    @State private var isEstimating = true
    @State private var usedFallback = false

    init(
        intelligence: IntelligenceService = FoundationModelsIntelligenceService.shared,
        onComplete: ((ThemeSelectionOutcome) -> Void)? = nil,
        onBack: (() -> Void)? = nil
    ) {
        self.intelligence = intelligence
        self.onComplete = onComplete
        self.onBack = onBack
    }

    public var body: some View {
        OnboardingPageScaffold(
            onBack: onBack,
            scrolls: true
        ) {
            // Uniform 32pt rhythm between every block: title → spinner/first
            // section, and section → section.
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                titleSection

                if isEstimating {
                    HStack(spacing: Spacing.sm) {
                        ProgressView()
                            .tint(theme.foreground)
                        Text("Finding themes that fit…")
                            .font(type.body2)
                            .foregroundStyle(theme.mutedForeground)
                    }
                    .accessibilityIdentifier("onboarding.themeEstimating")
                } else {
                    // All categories render immediately (Figma 618:3691 /
                    // 608:2240) — suggested themes just start selected in place.
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
            }
        } footer: {
            PrimaryButton(title: "Next step", systemImage: "arrow.right", imagePlacement: .trailing) {
                saveAndContinue()
            }
            .opacity(canContinue ? 1.0 : 0.5)
            .disabled(!canContinue || isEstimating)
            .accessibilityIdentifier("onboarding.continueThemes")
        }
        .task {
            await runEstimate()
        }
    }

    // MARK: - Subviews

    private var titleSection: some View {
        // Figma: title 20pt bold (h4), subtitle muted semibold.
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
                .accessibilityIdentifier("onboarding.theme.\(themeItem.id)")
            }
        }
    }

    private var canContinue: Bool {
        !selectedIds.isEmpty && selectedIds.count <= ThemeCatalog.maxConfirmedThemes
    }

    // MARK: - Actions

    private func toggle(_ id: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // The animated transaction is what makes the surrounding pills glide:
        // a toggled pill changes width (plus icon + weight), and ThemeFlowLayout
        // re-places its neighbors — without withAnimation that reflow snaps.
        // Same spring as SelectableThemeTag so the two never fight.
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if selectedIds.contains(id) {
                selectedIds.remove(id)
            } else if selectedIds.count < ThemeCatalog.maxConfirmedThemes {
                selectedIds.insert(id)
            }
        }
    }

    private func saveAndContinue() {
        guard canContinue else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let ordered = ThemeCatalog.validate(
            suggestedIds.filter { selectedIds.contains($0) } + selectedIds.filter { !suggestedIds.contains($0) }
        )
        onComplete?(ThemeSelectionOutcome(
            themeIds: ordered,
            promptLens: promptLens,
            suggestedIds: suggestedIds,
            modelIdentifier: estimateModelIdentifier,
            promptVersion: estimatePromptVersion
        ))
    }

    @MainActor
    private func runEstimate() async {
        isEstimating = true
        usedFallback = false
        let reflection = onboardingViewModel.personalizationText

        // Empty reflection → browse-only, no preselection.
        guard !reflection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            withAnimation(.easeInOut(duration: 0.25)) { isEstimating = false }
            usedFallback = true
            return
        }

        do {
            let result = try await intelligence.estimateProfile(reflection: reflection)
            suggestedIds = ThemeCatalog.validate(
                result.themeIds + result.secondaryThemeIds,
                max: ThemeCatalog.defaultSuggestionCount + 2
            )
            promptLens = result.promptLens.isEmpty ? nil : result.promptLens
            estimateModelIdentifier = result.modelIdentifier
            estimatePromptVersion = result.promptVersion
            selectedIds = Set(Array(suggestedIds.prefix(ThemeCatalog.defaultSuggestionCount)))
            usedFallback = false
        } catch {
            // Keyword overlap fallback when AFM is unavailable or fails.
            suggestedIds = ThemeCatalog.suggestFromKeywords(reflection)
            selectedIds = Set(suggestedIds)
            promptLens = nil
            // Keyword overlap is not a model — leave provenance nil rather than
            // stamping a model that did not produce this.
            estimateModelIdentifier = nil
            estimatePromptVersion = nil
            usedFallback = true
            AppLogger.log("⚠️ Theme estimate fell back to keywords: \(error.localizedDescription)")
        }

        // Animated swap: spinner eases out, sections (with suggested pills
        // already copper) ease in — no hard pop when the estimate lands.
        withAnimation(.easeInOut(duration: 0.25)) { isEstimating = false }
    }
}

#Preview("Theme confirmation") {
    ThemeConfirmationView()
        .useTheme()
        .useTypography()
        .environmentObject(OnboardingViewModel())
}
