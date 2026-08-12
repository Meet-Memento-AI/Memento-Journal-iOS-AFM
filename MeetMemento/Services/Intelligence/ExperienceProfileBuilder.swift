//
//  ExperienceProfileBuilder.swift
//  MeetMemento
//
//  Shared helper for building / rebuilding the local ExperienceProfile from
//  reflection + ThemeCatalog via IntelligenceService (no FoundationModels import).
//

import Foundation

enum ExperienceProfileBuilder {
    /// Rebuild the prompt lens (and optionally refresh suggested theme ids)
    /// from the current reflection. Preserves confirmed themes unless
    /// `replaceConfirmedWithSuggestions` is true.
    @MainActor
    static func rebuildLens(
        intelligence: IntelligenceService = FoundationModelsIntelligenceService.shared,
        replaceConfirmedWithSuggestions: Bool = false
    ) async throws -> ExperienceProfile {
        var profile = LocalProfileStore.ensureMigratedProfile()
        let reflection = profile.reflection?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !reflection.isEmpty else {
            // Nothing to estimate from — clear stale lens and return.
            profile.promptLens = nil
            profile.builtAt = Date()
            profile.catalogVersion = ThemeCatalog.catalogVersion
            LocalProfileStore.experienceProfile = profile
            return profile
        }

        do {
            let result = try await intelligence.estimateProfile(reflection: reflection)
            let suggested = ThemeCatalog.validate(
                result.themeIds + result.secondaryThemeIds,
                max: ThemeCatalog.defaultSuggestionCount + 2
            )
            profile.suggestedThemeIds = suggested
            var lens = result.promptLens.trimmingCharacters(in: .whitespacesAndNewlines)
            if lens.count > PromptRegistry.maxPromptLensChars {
                lens = String(lens.prefix(PromptRegistry.maxPromptLensChars))
            }
            profile.promptLens = lens.isEmpty ? nil : lens
            profile.modelIdentifier = result.modelIdentifier
            profile.promptVersion = result.promptVersion
            if replaceConfirmedWithSuggestions, !suggested.isEmpty {
                profile.confirmedThemeIds = ThemeCatalog.validate(
                    Array(suggested.prefix(ThemeCatalog.defaultSuggestionCount))
                )
            }
        } catch {
            // Keyword fallback when AFM is unavailable.
            let suggested = ThemeCatalog.suggestFromKeywords(reflection)
            profile.suggestedThemeIds = suggested
            profile.promptLens = Self.deterministicLens(
                themes: replaceConfirmedWithSuggestions ? suggested : profile.confirmedThemeIds
            )
            profile.modelIdentifier = "keyword-fallback"
            // No prompt ran, so there is no prompt version to claim.
            profile.promptVersion = nil
            if replaceConfirmedWithSuggestions, !suggested.isEmpty {
                profile.confirmedThemeIds = ThemeCatalog.validate(suggested)
            }
            AppLogger.log("⚠️ ExperienceProfileBuilder fell back to keywords: \(error.localizedDescription)")
        }

        // If themes exist but lens is still empty, synthesize a quiet lens.
        if (profile.promptLens?.isEmpty ?? true), !profile.confirmedThemeIds.isEmpty {
            profile.promptLens = Self.deterministicLens(themes: profile.confirmedThemeIds)
        }

        profile.catalogVersion = ThemeCatalog.catalogVersion
        profile.builtAt = Date()
        LocalProfileStore.experienceProfile = profile
        return profile
    }

    /// Rebuild lens from an already-updated set of confirmed theme ids,
    /// without changing the user's confirmed selection.
    @MainActor
    static func rebuildLensPreservingThemes(
        confirmedThemeIds: [String],
        reflection: String?,
        intelligence: IntelligenceService = FoundationModelsIntelligenceService.shared
    ) async throws -> ExperienceProfile {
        var profile = LocalProfileStore.experienceProfile ?? .empty
        profile.confirmedThemeIds = ThemeCatalog.validate(confirmedThemeIds)
        if let reflection {
            let trimmed = reflection.trimmingCharacters(in: .whitespacesAndNewlines)
            profile.reflection = trimmed.isEmpty ? nil : trimmed
        }
        LocalProfileStore.experienceProfile = profile
        return try await rebuildLens(
            intelligence: intelligence,
            replaceConfirmedWithSuggestions: false
        )
    }

    /// Quiet third-person lens when AFM is unavailable.
    static func deterministicLens(themes: [String]) -> String? {
        let names = ThemeCatalog.displayNames(for: themes)
        guard !names.isEmpty else { return nil }
        let joined = names.joined(separator: ", ")
        return "Lean toward noticing patterns around \(joined). Prefer open questions over advice."
    }
}
