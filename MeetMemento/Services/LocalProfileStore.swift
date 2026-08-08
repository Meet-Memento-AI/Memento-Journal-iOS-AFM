//
//  LocalProfileStore.swift
//  MeetMemento
//
//  Local-only storage for personalization text, journal themes, and the
//  ExperienceProfile used to refine on-device prompts (spec 023 / 024).
//

import Foundation

enum LocalProfileStore {
    private static let personalizationTextKey = "memento_personalization_text"
    private static let selectedGoalsKey = "memento_selected_goals"
    private static let experienceProfileKey = "memento_experience_profile"

    // MARK: - Compatibility accessors (reflection + display names)

    static var personalizationText: String? {
        get {
            if let profile = experienceProfile, let reflection = profile.reflection, !reflection.isEmpty {
                return reflection
            }
            return UserDefaults.standard.string(forKey: personalizationTextKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: personalizationTextKey)
            var profile = experienceProfile ?? .empty
            profile.reflection = newValue
            profile.builtAt = Date()
            profile.catalogVersion = ThemeCatalog.catalogVersion
            experienceProfile = profile
        }
    }

    /// Display names of confirmed themes (legacy "goals" shape for older call sites).
    static var selectedGoals: [String] {
        get {
            let profile = ensureMigratedProfile()
            let names = profile.confirmedThemeNames
            if !names.isEmpty { return names }
            return UserDefaults.standard.stringArray(forKey: selectedGoalsKey) ?? []
        }
        set {
            // Accept either theme ids or legacy/display names.
            let ids = newValue.compactMap { raw -> String? in
                if ThemeCatalog.theme(id: raw) != nil { return raw }
                return ThemeCatalog.legacyGoalMapping(raw)
            }
            var profile = experienceProfile ?? .empty
            profile.confirmedThemeIds = ThemeCatalog.validate(ids)
            profile.builtAt = Date()
            profile.catalogVersion = ThemeCatalog.catalogVersion
            experienceProfile = profile
            // Keep legacy key populated with display names for any leftover readers.
            UserDefaults.standard.set(profile.confirmedThemeNames, forKey: selectedGoalsKey)
        }
    }

    // MARK: - Experience profile

    static var experienceProfile: ExperienceProfile? {
        get {
            guard let data = UserDefaults.standard.data(forKey: experienceProfileKey) else {
                return nil
            }
            return try? JSONDecoder().decode(ExperienceProfile.self, from: data)
        }
        set {
            if let newValue {
                if let data = try? JSONEncoder().encode(newValue) {
                    UserDefaults.standard.set(data, forKey: experienceProfileKey)
                }
                // Mirror compatibility keys.
                if let reflection = newValue.reflection {
                    UserDefaults.standard.set(reflection, forKey: personalizationTextKey)
                }
                UserDefaults.standard.set(newValue.confirmedThemeNames, forKey: selectedGoalsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: experienceProfileKey)
            }
        }
    }

    /// Loads the profile, migrating legacy goals/reflection once if needed.
    @discardableResult
    static func ensureMigratedProfile() -> ExperienceProfile {
        if var existing = experienceProfile, !existing.confirmedThemeIds.isEmpty || existing.reflection != nil {
            // Re-validate ids against current catalog.
            existing.confirmedThemeIds = ThemeCatalog.validate(existing.confirmedThemeIds)
            existing.suggestedThemeIds = ThemeCatalog.validate(existing.suggestedThemeIds, max: 12)
            return existing
        }

        let legacyReflection = UserDefaults.standard.string(forKey: personalizationTextKey)
        let legacyGoals = UserDefaults.standard.stringArray(forKey: selectedGoalsKey) ?? []
        let mappedIds = ThemeCatalog.validate(legacyGoals.compactMap { ThemeCatalog.legacyGoalMapping($0) })

        var migrated = ExperienceProfile.empty
        migrated.reflection = legacyReflection
        migrated.confirmedThemeIds = mappedIds
        migrated.catalogVersion = ThemeCatalog.catalogVersion
        migrated.builtAt = Date()
        if !migrated.isEmpty {
            experienceProfile = migrated
        }
        return migrated
    }

    /// Clears all locally stored profile data. Used by "Delete everything" (spec 023 R4).
    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: personalizationTextKey)
        UserDefaults.standard.removeObject(forKey: selectedGoalsKey)
        UserDefaults.standard.removeObject(forKey: experienceProfileKey)
    }
}
