//
//  ProfileRefreshCoordinator.swift
//  MeetMemento
//
//  Session 11 / 044 R6: consent-gated lens proposal. Never runs during Ask.
//

import Foundation

enum ProfileRefreshCoordinator {
    static let minimumDays = 14
    static let minimumNewEntries = 10

    static func isDue(
        profile: ExperienceProfile,
        entries: [Entry],
        now: Date = Date()
    ) -> Bool {
        guard profile.builtAt > .distantPast else { return false }
        let days = now.timeIntervalSince(profile.builtAt) / 86_400
        guard days >= Double(minimumDays) else { return false }
        let fresh = entries.filter { $0.createdAt > profile.builtAt }.count
        return fresh >= minimumNewEntries
    }

    static func refreshIfDue(
        entries: [Entry],
        intelligence: IntelligenceService = FoundationModelsIntelligenceService.shared,
        now: Date = Date()
    ) async {
        guard PreferencesService.shared.aiEnabled else { return }
        var profile = LocalProfileStore.ensureMigratedProfile()
        guard isDue(profile: profile, entries: entries, now: now) else { return }
        guard profile.proposedPromptLens == nil else { return }

        do {
            let result = try await intelligence.refreshProfile(entries: entries, current: profile)
            var lens = result.promptLens.trimmingCharacters(in: .whitespacesAndNewlines)
            if lens.count > PromptRegistry.maxGeneratedPromptLensChars {
                lens = String(lens.prefix(PromptRegistry.maxGeneratedPromptLensChars)) // budget-exempt: stored-lens cap
            }
            if lens.isEmpty { return }
            if OutputSafetyScanner.scan(lens) != nil { return }
            if containsForbiddenPhrase(lens) { return }
            profile.proposedPromptLens = lens
            profile.proposedModelIdentifier = result.modelIdentifier
            profile.proposedPromptVersion = result.promptVersion
            LocalProfileStore.experienceProfile = profile
        } catch {
            AppLogger.log("Profile refresh skipped: \(error.localizedDescription)")
        }
    }

    static func acceptProposal() {
        var profile = LocalProfileStore.ensureMigratedProfile()
        guard let proposed = profile.proposedPromptLens, !proposed.isEmpty else { return }
        profile.promptLens = proposed
        profile.modelIdentifier = profile.proposedModelIdentifier
        profile.promptVersion = profile.proposedPromptVersion
        profile.builtAt = Date()
        clearProposal(&profile)
        LocalProfileStore.experienceProfile = profile
    }

    static func keepMine() {
        var profile = LocalProfileStore.ensureMigratedProfile()
        clearProposal(&profile)
        LocalProfileStore.experienceProfile = profile
    }

    static func editProposal(_ lens: String) {
        var profile = LocalProfileStore.ensureMigratedProfile()
        let trimmed = String(lens.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(PromptRegistry.maxGeneratedPromptLensChars)) // budget-exempt: stored-lens cap
        guard !trimmed.isEmpty else { return }
        if OutputSafetyScanner.scan(trimmed) != nil { return }
        if containsForbiddenPhrase(trimmed) { return }
        profile.promptLens = trimmed
        profile.modelIdentifier = profile.proposedModelIdentifier ?? "user-edit"
        profile.promptVersion = profile.proposedPromptVersion
        profile.builtAt = Date()
        clearProposal(&profile)
        LocalProfileStore.experienceProfile = profile
    }

    private static func clearProposal(_ profile: inout ExperienceProfile) {
        profile.proposedPromptLens = nil
        profile.proposedModelIdentifier = nil
        profile.proposedPromptVersion = nil
    }

    /// Mirrors `scripts/ci/lint_forbidden_phrases.py` advice stems used on starters.
    static func containsForbiddenPhrase(_ text: String) -> Bool {
        let lower = text.lowercased()
        let banned = [
            "you should", "create an actionable plan", "try these breathing",
            "as your therapist", "coping protocol", "you always", "you never"
        ]
        return banned.contains { lower.contains($0) }
    }
}
