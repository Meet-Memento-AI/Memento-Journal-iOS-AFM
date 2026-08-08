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
        suggestedIds: [String]
    ) async throws {
        isProcessing = true
        defer { isProcessing = false }

        let validated = ThemeCatalog.validate(themeIds)
        guard !validated.isEmpty else { return }

        confirmedThemeIds = validated
        suggestedThemeIds = ThemeCatalog.validate(suggestedIds, max: 12)
        self.promptLens = promptLens
        selectedGoals = ThemeCatalog.displayNames(for: validated)

        let trimmedReflection = personalizationText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLens = promptLens?.trimmingCharacters(in: .whitespacesAndNewlines)

        var profile = LocalProfileStore.experienceProfile ?? .empty
        profile.reflection = trimmedReflection.isEmpty ? nil : trimmedReflection
        profile.confirmedThemeIds = validated
        profile.suggestedThemeIds = suggestedThemeIds
        profile.promptLens = (trimmedLens?.isEmpty == false) ? trimmedLens : nil
        profile.catalogVersion = ThemeCatalog.catalogVersion
        profile.builtAt = Date()
        LocalProfileStore.experienceProfile = profile
        hasGoals = true

        AppLogger.log("✅ [OnboardingViewModel] Experience profile saved: \(validated)")
    }

    /// Creates the first journal entry from the personalization text via the
    /// shared `EntryViewModel` local-first create path (spec 023 — no
    /// account, and per `createEntry`'s comment, the network attempt fails
    /// gracefully and queues for retry rather than losing the entry).
    func createFirstJournalEntry(text: String, using entryViewModel: EntryViewModel) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        entryViewModel.createEntry(title: "My First Reflection", text: trimmed)

                AppLogger.log("✅ [OnboardingViewModel] First journal entry created locally")
    }

    /// Marks onboarding as complete locally.
    func completeOnboarding() async throws {
                AppLogger.log("✅ [OnboardingViewModel] Onboarding marked complete locally")
    }
}
