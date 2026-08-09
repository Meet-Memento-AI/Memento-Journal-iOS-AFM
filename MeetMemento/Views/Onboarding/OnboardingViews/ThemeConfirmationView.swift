//
//  ThemeConfirmationView.swift
//  MeetMemento
//
//  Onboarding step: AFM (or keyword fallback) suggests ThemeCatalog themes
//  from the LearnAboutYourself reflection; user confirms/edits before continue.
//

import SwiftUI

public struct ThemeConfirmationView: View {
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @EnvironmentObject var onboardingViewModel: OnboardingViewModel

    public var onComplete: ((_ themeIds: [String], _ promptLens: String?, _ suggestedIds: [String]) -> Void)?
    public var onBack: (() -> Void)?
    public var intelligence: IntelligenceService

    @State private var selectedIds: Set<String> = []
    @State private var suggestedIds: [String] = []
    @State private var promptLens: String?
    @State private var isEstimating = true
    @State private var usedFallback = false
    @State private var showAllThemes = false

    public init(
        intelligence: IntelligenceService = FoundationModelsIntelligenceService.shared,
        onComplete: ((_ themeIds: [String], _ promptLens: String?, _ suggestedIds: [String]) -> Void)? = nil,
        onBack: (() -> Void)? = nil
    ) {
        self.intelligence = intelligence
        self.onComplete = onComplete
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

                        if isEstimating {
                            HStack(spacing: 12) {
                                ProgressView()
                                    .tint(theme.primary)
                                Text("Finding themes that fit…")
                                    .font(type.body2)
                                    .foregroundStyle(theme.mutedForeground)
                            }
                            .padding(.top, 32)
                            .accessibilityIdentifier("onboarding.themeEstimating")
                        } else {
                            if usedFallback {
                                Text("Pick the themes that feel right — you can change these anytime.")
                                    .font(type.body2)
                                    .foregroundStyle(theme.mutedForeground)
                                    .padding(.top, 12)
                            }

                            if !suggestedThemes.isEmpty {
                                sectionLabel("Suggested for you")
                                    .padding(.top, 24)
                                themeChipFlow(suggestedThemes)
                                    .padding(.top, 12)
                            }

                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showAllThemes.toggle()
                                }
                            } label: {
                                Text(showAllThemes ? "Hide full catalog" : "Browse all themes")
                                    .font(type.body2Bold)
                                    .foregroundStyle(theme.primary)
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
                                            .padding(.top, 12)
                                    }
                                }
                            }
                        }

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
                .disabled(!canContinue || isEstimating)
                .accessibilityIdentifier("onboarding.continueThemes")
                .padding(.horizontal, 16)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await runEstimate()
        }
    }

    // MARK: - Subviews

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 12) {
            IconButtonNav(
                icon: "chevron.left",
                iconSize: 20,
                buttonSize: 40,
                foregroundColor: theme.foreground,
                useDarkBackground: false,
                enableHaptic: true,
                onTap: { onBack?() }
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
        ThemeFlowLayout(spacing: 12) {
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
        onComplete?(ordered, promptLens, suggestedIds)
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
            selectedIds = Set(Array(suggestedIds.prefix(ThemeCatalog.defaultSuggestionCount)))
            usedFallback = false
        } catch {
            // Keyword overlap fallback when AFM is unavailable or fails.
            suggestedIds = ThemeCatalog.suggestFromKeywords(reflection)
            selectedIds = Set(suggestedIds)
            promptLens = nil
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
