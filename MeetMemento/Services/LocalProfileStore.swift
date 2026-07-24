//
//  LocalProfileStore.swift
//  MeetMemento
//
//  Local-only storage for personalization text and journal goals, replacing
//  the Supabase-backed UserService calls from onboarding and the drawer
//  editors (spec 023 — no accounts, nothing to sync to a server).
//

import Foundation

enum LocalProfileStore {
    private static let personalizationTextKey = "memento_personalization_text"
    private static let selectedGoalsKey = "memento_selected_goals"

    static var personalizationText: String? {
        get { UserDefaults.standard.string(forKey: personalizationTextKey) }
        set { UserDefaults.standard.set(newValue, forKey: personalizationTextKey) }
    }

    static var selectedGoals: [String] {
        get { UserDefaults.standard.stringArray(forKey: selectedGoalsKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: selectedGoalsKey) }
    }

    /// Clears all locally stored profile data. Used by "Delete everything" (spec 023 R4).
    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: personalizationTextKey)
        UserDefaults.standard.removeObject(forKey: selectedGoalsKey)
    }
}
