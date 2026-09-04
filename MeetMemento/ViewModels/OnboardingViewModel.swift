//
//  OnboardingViewModel.swift
//  MeetMemento
//
//  Manages onboarding state and persists data locally (spec 023 — no accounts,
//  nothing to sync to a server).
//

import Foundation
import SwiftUI

@MainActor
class OnboardingViewModel: ObservableObject {
    // User profile
    @Published var firstName = ""
    @Published var lastName = ""

    // Personalization
    @Published var personalizationText = ""

    // Themes / experience profile
    @Published var selectedGoals: [String] = []
    @Published var confirmedThemeIds: [String] = []
    @Published var suggestedThemeIds: [String] = []
    @Published var promptLens: String?

    // Security
    @Published var useFaceID = false
    @Published var setupPin = ""
    @Published var confirmedPin = ""

    // State tracking
    @Published var hasProfile = false
    @Published var hasPersonalization = false
    @Published var hasGoals = false
    @Published var isLoadingState = false
    @Published var isProcessing = false
    @Published var errorMessage: String?

    var shouldStartAtProfile: Bool { !hasProfile }
    var shouldStartAtPersonalization: Bool { hasProfile && !hasPersonalization }
    var shouldStartAtGoals: Bool { hasProfile && hasPersonalization && !hasGoals }

    /// Loads the user's current onboarding progress from local storage so the
    /// coordinator can resume at the correct step (e.g. if onboarding was
    /// interrupted and the app relaunched).
    func loadCurrentState() async {
        let cachedFirstName = UserDefaults.standard.string(forKey: "memento_first_name")
        let cachedLastName = UserDefaults.standard.string(forKey: "memento_last_name")
        if let cachedFirstName, !cachedFirstName.isEmpty {
            hasProfile = true
            firstName = cachedFirstName
            lastName = cachedLastName ?? ""
        }

        if let text = LocalProfileStore.personalizationText, !text.isEmpty {
            hasPersonalization = true
            personalizationText = text
        }

        let profile = LocalProfileStore.ensureMigratedProfile()
        if !profile.confirmedThemeIds.isEmpty {
            hasGoals = true
            confirmedThemeIds = profile.confirmedThemeIds
            suggestedThemeIds = profile.suggestedThemeIds
            promptLens = profile.promptLens
            selectedGoals = profile.confirmedThemeNames
        } else {
            let goals = LocalProfileStore.selectedGoals
            if !goals.isEmpty {
                hasGoals = true
                selectedGoals = goals
            }
        }
    }

    /// Persists the user's first and last name locally.
    func saveProfileData() async throws {
        isProcessing = true
        defer { isProcessing = false }

        UserDefaults.standard.set(firstName, forKey: "memento_first_name")
        UserDefaults.standard.set(lastName, forKey: "memento_last_name")
        hasProfile = true

                AppLogger.log("✅ [OnboardingViewModel] Profile saved locally: \(firstName) \(lastName)")
    }

    /// Persists the personalization reflection text locally.
    func savePersonalizationText() async throws {
        guard !personalizationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        LocalProfileStore.personalizationText = personalizationText.trimmingCharacters(in: .whitespacesAndNewlines)
        hasPersonalization = true

                AppLogger.log("✅ [OnboardingViewModel] Personalization text saved locally")
    }

    /// Persists the ExperienceProfile (confirmed ThemeCatalog ids + optional lens).
    func saveExperienceProfile(
        themeIds: [String],
        promptLens: String?,
        suggestedIds: [String],
        modelIdentifier: String? = nil,
        promptVersion: String? = nil
    ) async throws {
        isProcessing = true
        defer { isProcessing = false }

        let validated = ThemeCatalog.validate(themeIds)
        guard !validated.isEmpty else { return }

        confirmedThemeIds = validated
        suggestedThemeIds = ThemeCatalog.validate(suggestedIds, max: 12)
        selectedGoals = ThemeCatalog.displayNames(for: validated)

        let trimmedReflection = personalizationText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLens = promptLens?.trimmingCharacters(in: .whitespacesAndNewlines)

        // Keep the AFM lens only when confirmed themes still overlap suggestions;
        // otherwise align the lens to what the user actually confirmed.
        let overlapsSuggestions = !Set(validated).isDisjoint(with: Set(suggestedThemeIds))
        let resolvedLens: String?
        if overlapsSuggestions, let trimmedLens, !trimmedLens.isEmpty {
            resolvedLens = trimmedLens
        } else {
            resolvedLens = ExperienceProfileBuilder.deterministicLens(themes: validated)
        }
        self.promptLens = resolvedLens

        var profile = LocalProfileStore.experienceProfile ?? .empty
        profile.reflection = trimmedReflection.isEmpty ? nil : trimmedReflection
        profile.confirmedThemeIds = validated
        profile.suggestedThemeIds = suggestedThemeIds
        profile.promptLens = resolvedLens
        profile.catalogVersion = ThemeCatalog.catalogVersion
        profile.builtAt = Date()
        // REQ-PRM-004: stamp what produced the lens. Onboarding previously left
        // these nil, so a profile built here had no provenance at all and only a
        // later ExperienceProfileBuilder rebuild ever recorded any. When the
        // estimate fell back to keyword overlap the caller passes nil, and the
        // deterministic lens below is likewise not model output — so nil is the
        // honest value, not a gap to fill.
        if resolvedLens == trimmedLens {
            profile.modelIdentifier = modelIdentifier
            profile.promptVersion = promptVersion
        } else {
            profile.modelIdentifier = nil
            profile.promptVersion = nil
        }
        LocalProfileStore.experienceProfile = profile
        hasGoals = true

        AppLogger.log("✅ [OnboardingViewModel] Experience profile saved: \(validated)")
    }

    /// Marks onboarding as complete locally.
    func completeOnboarding() async throws {
                AppLogger.log("✅ [OnboardingViewModel] Onboarding marked complete locally")
    }
}
