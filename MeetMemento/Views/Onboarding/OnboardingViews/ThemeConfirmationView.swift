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
    @State private var showAllThemes = false

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
            VStack(alignment: .leading, spacing: 0) {
                titleSection

                if isEstimating {
                    HStack(spacing: 12) {
                        ProgressView()
                            .tint(theme.foreground)
                        Text("Finding themes that fit…")
                            .font(type.body2)
                            .foregroundStyle(theme.mutedForeground)
                    }
                    .padding(.top, OnboardingLayout.sectionSpacing)
                    .accessibilityIdentifier("onboarding.themeEstimating")
                } else {
                    if usedFallback {
                        Text("Pick the themes that feel right — you can change these anytime.")
                            .font(type.body2)
                            .foregroundStyle(theme.mutedForeground)
                            .padding(.top, OnboardingLayout.titleBodySpacing)
                    }

                    if !suggestedThemes.isEmpty {
                        sectionLabel("Suggested for you")
                            .padding(.top, OnboardingLayout.sectionSpacing)
                        themeChipFlow(suggestedThemes)
                            .padding(.top, OnboardingLayout.titleBodySpacing)
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showAllThemes.toggle()
                        }
                    } label: {
                        Text(showAllThemes ? "Hide full catalog" : "Browse all themes")
                            .font(type.body2Bold)
                            .foregroundStyle(theme.foreground)
                    }
                    .padding(.top, 20)
                    .accessibilityIdentifier("onboarding.browseThemes")

                    if showAllThemes {
                        ForEach(ThemeFamily.allCases) { family in
                            let themes = ThemeCatalog.themes(in: family)
                            if !themes.isEmpty {
                                sectionLabel(family.title)
                                    .padding(.top, 20)
                                themeChipFlow(themes)
                                    .padding(.top, OnboardingLayout.titleBodySpacing)
                            }
                        }
                    }
                }
            }
        } footer: {
            PrimaryButton(title: "Continue") {
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
        VStack(alignment: .leading, spacing: OnboardingLayout.titleBodySpacing) {
            Text("Themes for your journal")
                .font(type.h3)
                .foregroundStyle(theme.foreground)

            Text("Based on what you shared, here are one-word themes to shape your experience. Select up to \(ThemeCatalog.maxConfirmedThemes).")
                .font(type.body1)
                .foregroundStyle(theme.mutedForeground)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(type.body2Bold)
            .foregroundStyle(theme.foreground)
    }

    private func themeChipFlow(_ themes: [JournalTheme]) -> some View {
        ThemeFlowLayout(spacing: OnboardingLayout.titleBodySpacing) {
            ForEach(themes) { themeItem in
                Chip(
                    text: themeItem.displayName,
                    isSelected: selectedIds.contains(themeItem.id),
                    onTap: { toggle(themeItem.id) }
                )
                .accessibilityIdentifier("onboarding.theme.\(themeItem.id)")
            }
        }
    }

    private var suggestedThemes: [JournalTheme] {
        ThemeCatalog.themes(ids: suggestedIds)
    }

    private var canContinue: Bool {
        !selectedIds.isEmpty && selectedIds.count <= ThemeCatalog.maxConfirmedThemes
    }

    // MARK: - Actions

    private func toggle(_ id: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else if selectedIds.count < ThemeCatalog.maxConfirmedThemes {
            selectedIds.insert(id)
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
            isEstimating = false
            showAllThemes = true
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
            if suggestedIds.isEmpty {
                showAllThemes = true
            }
            AppLogger.log("⚠️ Theme estimate fell back to keywords: \(error.localizedDescription)")
        }

        isEstimating = false
    }
}

// MARK: - Flow layout (local to this screen)

private struct ThemeFlowLayout: Layout {
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

#Preview("Theme confirmation") {
    ThemeConfirmationView()
        .useTheme()
        .useTypography()
        .environmentObject(OnboardingViewModel())
}
