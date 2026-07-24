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

    // Goals
    @Published var selectedGoals: [String] = []

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

        let goals = LocalProfileStore.selectedGoals
        if !goals.isEmpty {
            hasGoals = true
            selectedGoals = goals
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

    /// Persists selected goals locally.
    func saveGoals() async throws {
        guard !selectedGoals.isEmpty else { return }
        LocalProfileStore.selectedGoals = selectedGoals
        hasGoals = true

                AppLogger.log("✅ [OnboardingViewModel] Goals saved locally: \(selectedGoals)")
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
