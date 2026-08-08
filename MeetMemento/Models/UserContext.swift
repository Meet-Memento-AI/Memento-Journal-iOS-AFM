
import Foundation

/// Represents onboarding context and reflection data from the `user_profiles` table.
/// Naming note: The DB table is `user_profiles`, but maps to user context/onboarding data, distinct from the main `users` profile.
public struct UserContext: Codable, Hashable {
    public let userId: UUID
    public var onboardingSelfReflection: String?
    public var selectedGoals: [String]?
    public var identifiedThemes: [String]?
    public var themeSelectionCount: Int?
    public var themesAnalyzedAt: Date?
    public let createdAt: Date?
    public var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case onboardingSelfReflection = "onboarding_self_reflection"
        case selectedGoals = "selected_goals"
        case identifiedThemes = "identified_themes"
        case themeSelectionCount = "theme_selection_count"
        case themesAnalyzedAt = "themes_analyzed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(
        userId: UUID,
        onboardingSelfReflection: String? = nil,
        selectedGoals: [String]? = nil,
        identifiedThemes: [String]? = nil,
        themeSelectionCount: Int? = 0,
        themesAnalyzedAt: Date? = nil,
        createdAt: Date? = Date(),
        updatedAt: Date? = Date()
    ) {
        self.userId = userId
        self.onboardingSelfReflection = onboardingSelfReflection
        self.selectedGoals = selectedGoals
        self.identifiedThemes = identifiedThemes
        self.themeSelectionCount = themeSelectionCount
        self.themesAnalyzedAt = themesAnalyzedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Context for system prompt personalization (LearnAboutYourselfView + ThemeCatalog themes)
    public var systemPromptContext: (onboardingSelfReflection: String?, selectedGoals: [String])? {
        let reflection = onboardingSelfReflection?.trimmingCharacters(in: .whitespacesAndNewlines)
        let goals = selectedGoals ?? []
        if reflection != nil || !goals.isEmpty {
            return (reflection, goals)
        }
        return nil
    }
}

// MARK: - Mocks
extension UserContext {
    public static let mock = UserContext(
        userId: UUID(),
        onboardingSelfReflection: "I want to stress less.",
        selectedGoals: ["Awareness", "Stress"],
        identifiedThemes: ["anxiety", "work"],
        themeSelectionCount: 2
    )
}
