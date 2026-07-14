//
//  OnboardingViewModel.swift
//  MeetMemento
//
//  Manages onboarding state and persists data to Supabase.
//

import Foundation
import SwiftUI
import Supabase

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

    private var client: SupabaseClient {
        SupabaseService.shared.client
    }

    /// Loads the user's current onboarding progress from the database so the
    /// coordinator can resume at the correct step.
    func loadCurrentState() async {
        do {
            if let profile = try await UserService.shared.getCurrentProfile() {
                let namePresent = profile.fullName != nil && !(profile.fullName?.isEmpty ?? true)
                hasProfile = namePresent

                let goalsPresent = profile.selectedTopics != nil && !(profile.selectedTopics?.isEmpty ?? true)
                hasGoals = goalsPresent

                if namePresent, let fn = profile.fullName {
                    let parts = fn.split(separator: " ", maxSplits: 1)
                    firstName = String(parts.first ?? "")
                    lastName = parts.count > 1 ? String(parts.last ?? "") : ""
                }
            }

            if let reflection = try await UserService.shared.getPersonalizationText() {
                hasPersonalization = !reflection.isEmpty
                personalizationText = reflection
            }
        } catch {
            AppLogger.log("⚠️ [OnboardingViewModel] Failed to load state: \(error)")
        }
    }

    /// Persists the user's first and last name to the `users` table.
    func saveProfileData() async throws {
        isProcessing = true
        defer { isProcessing = false }

        try await UserService.shared.updateFullName(firstName: firstName, lastName: lastName)
        hasProfile = true

                AppLogger.log("✅ [OnboardingViewModel] Profile saved: \(firstName) \(lastName)")
    }

    /// Persists the personalization reflection text to `user_profiles`.
    func savePersonalizationText() async throws {
        guard !personalizationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        try await UserService.shared.savePersonalizationText(
            personalizationText.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        hasPersonalization = true

                AppLogger.log("✅ [OnboardingViewModel] Personalization text saved")
    }

    /// Persists selected goals to the `users` table.
    func saveGoals() async throws {
        guard !selectedGoals.isEmpty else { return }
        try await UserService.shared.updateGoals(selectedGoals)
        hasGoals = true

                AppLogger.log("✅ [OnboardingViewModel] Goals saved: \(selectedGoals)")
    }

    /// Creates the first journal entry from the personalization text.
    func createFirstJournalEntry(text: String) async throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let userId = client.auth.currentUser?.id else { return }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = "My First Reflection"
        let entry = JournalEntry(
            userId: userId,
            title: title,
            content: trimmed,
            wordCount: trimmed.split(separator: " ").count
        )
        try await JournalService.shared.createEntry(entry)

                AppLogger.log("✅ [OnboardingViewModel] First journal entry created")
    }

    /// Marks onboarding as complete in the database.
    func completeOnboarding() async throws {
        try await UserService.shared.markOnboardingComplete()

                AppLogger.log("✅ [OnboardingViewModel] Onboarding marked complete in DB")
    }
}
