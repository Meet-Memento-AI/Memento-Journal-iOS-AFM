//
//  PreferencesService.swift
//  MeetMemento
//
//  User preferences for theme and feature toggles.
//

import Foundation
import Combine

/// User preferences service for app-wide settings
class PreferencesService: ObservableObject {
    static let shared = PreferencesService()

    private let defaults = UserDefaults.standard

    // MARK: - Keys
    private enum Keys {
        static let themePreference = "themePreference"
        static let aiEnabled = "aiEnabled"
    }

    // MARK: - Published Properties
    @Published var aiEnabled: Bool {
        didSet {
            defaults.set(aiEnabled, forKey: Keys.aiEnabled)
        }
    }

    // MARK: - Theme Preference
    var themePreference: AppThemePreference {
        get {
            let rawValue = defaults.string(forKey: Keys.themePreference) ?? "system"
            return AppThemePreference(rawValue: rawValue) ?? .system
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.themePreference)
        }
    }

    // MARK: - Initialization
    private init() {
        // Initialize aiEnabled from stored value, default to true
        let storedEnabled = defaults.object(forKey: Keys.aiEnabled) as? Bool
        self.aiEnabled = storedEnabled ?? true
    }

    /// Resets preferences to defaults. Used by "Delete everything" (spec 023 R4).
    func resetToDefaults() {
        defaults.removeObject(forKey: Keys.themePreference)
        defaults.removeObject(forKey: Keys.aiEnabled)
        aiEnabled = true
    }
}
