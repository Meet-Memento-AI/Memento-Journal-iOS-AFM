//
//  ThemeCatalog.swift
//  MeetMemento
//
//  Product-owned, closed vocabulary of journaling themes.
//  AFM theme estimation may only return IDs from this catalog.
//
//  themes@2 restructures the taxonomy to the Figma onboarding design
//  (file 6jxgJ60YK0E6F8T04bx2q8, frames 618:3691 / 608:2240): five
//  categories, eight topics each. Display names may be multi-word.
//  Profiles stored under themes@1 degrade gracefully — `validate` drops
//  ids the new catalog doesn't know.
//

import Foundation

/// A single journaling theme from the predetermined catalog.
struct JournalTheme: Identifiable, Hashable, Sendable, Codable {
    /// Stable machine id (snake_case). Never shown raw in UI.
    let id: String
    /// Short display label shown on chips.
    let displayName: String
    /// Grouping for browse UI.
    let family: ThemeFamily
    /// Optional synonyms used for offline/keyword fallback matching.
    let synonyms: [String]
}

enum ThemeFamily: String, CaseIterable, Sendable, Codable, Identifiable {
    case mentalHealth = "mental_health"
    case careerGrowth = "career_growth"
    case creativity
    case relationships
    case physicalHealth = "physical_health"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mentalHealth: return "Mental Health"
        case .careerGrowth: return "Career Growth"
        case .creativity: return "Creativity"
        case .relationships: return "Relationships"
        case .physicalHealth: return "Physical Health"
        }
    }
}

/// Bundled theme taxonomy. `catalogVersion` bumps when ids/labels change meaningfully.
enum ThemeCatalog {
    static let catalogVersion = "themes@2"

    /// Max themes a user may confirm (keeps the prompt lens focused).
    static let maxConfirmedThemes = 6

    /// Default number of AFM suggestions to preselect.
    static let defaultSuggestionCount = 4

    static let all: [JournalTheme] = [
        // Mental Health
        theme("anxiety", "Anxiety", .mentalHealth, ["worry", "nervousness", "panic"]),
        theme("self_esteem", "Self-Esteem", .mentalHealth, ["confidence", "worth", "value"]),
        theme("mindfulness", "Mindfulness", .mentalHealth, ["meditation", "attention", "presence", "awareness"]),
        theme("stress", "Stress", .mentalHealth, ["pressure", "overwhelm", "tension", "burnout"]),
        theme("boundaries", "Boundaries", .mentalHealth, ["limits", "saying", "protect"]),
        theme("gratitude", "Gratitude", .mentalHealth, ["thankful", "appreciation"]),
        theme("sleep", "Sleep", .mentalHealth, ["rest", "insomnia", "tired"]),
        theme("therapy", "Therapy", .mentalHealth, ["counseling", "healing", "feelings"]),

        // Career Growth
        theme("goals", "Goals", .careerGrowth, ["ambition", "targets", "plans"]),
        theme("networking", "Networking", .careerGrowth, ["connections", "contacts"]),
        theme("skills", "Skills", .careerGrowth, ["learning", "practice", "improve"]),
        theme("work_life_balance", "Work-Life Balance", .careerGrowth, ["balance", "work", "overwork"]),
        theme("leadership", "Leadership", .careerGrowth, ["managing", "leading", "team"]),
        theme("motivation", "Motivation", .careerGrowth, ["drive", "discipline", "focus"]),
        theme("side_projects", "Side Projects", .careerGrowth, ["project", "building", "hustle"]),
        theme("mentorship", "Mentorship", .careerGrowth, ["mentor", "guidance", "advice"]),

        // Creativity
        theme("inspiration", "Inspiration", .creativity, ["ideas", "spark", "muse"]),
        theme("writing", "Writing", .creativity, ["journaling", "stories", "poetry"]),
        theme("visual_arts", "Visual Arts", .creativity, ["drawing", "painting", "design"]),
        theme("music", "Music", .creativity, ["songs", "playing", "listening"]),
        theme("brainstorming", "Brainstorming", .creativity, ["ideation", "thinking"]),
        theme("creative_blocks", "Creative Blocks", .creativity, ["stuck", "blocked"]),
        theme("collaboration", "Collaboration", .creativity, ["together", "cocreating"]),
        theme("experimentation", "Experimentation", .creativity, ["trying", "exploring", "curiosity"]),

        // Relationships
        theme("friendship", "Friendship", .relationships, ["friends", "connection"]),
        theme("family", "Family", .relationships, ["parents", "siblings", "home"]),
        theme("romance", "Romance", .relationships, ["partner", "dating", "love"]),
        theme("communication", "Communication", .relationships, ["talking", "listening", "expression"]),
        theme("conflict", "Conflict", .relationships, ["argument", "tension", "disagreement"]),
        theme("trust", "Trust", .relationships, ["honesty", "loyalty", "openness"]),
        theme("belonging", "Belonging", .relationships, ["community", "acceptance", "loneliness"]),
        theme("support", "Support", .relationships, ["help", "care", "compassion"]),

        // Physical Health
        theme("exercise", "Exercise", .physicalHealth, ["workout", "fitness", "training"]),
        theme("nutrition", "Nutrition", .physicalHealth, ["food", "eating", "diet"]),
        theme("rest", "Rest", .physicalHealth, ["recovery", "pause", "recharge"]),
        theme("energy", "Energy", .physicalHealth, ["vitality", "fatigue", "tired"]),
        theme("movement", "Movement", .physicalHealth, ["walking", "stretching", "active"]),
        theme("recovery", "Recovery", .physicalHealth, ["healing", "injury", "rehab"]),
        theme("body_image", "Body Image", .physicalHealth, ["body", "appearance", "acceptance"]),
        theme("wellness", "Wellness", .physicalHealth, ["health", "habits", "selfcare"]),
    ]

    // MARK: - Lookups

    private static let byId: [String: JournalTheme] = {
        Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    }()

    private static let byDisplayNameLowercased: [String: JournalTheme] = {
        Dictionary(uniqueKeysWithValues: all.map { ($0.displayName.lowercased(), $0) })
    }()

    static func theme(id: String) -> JournalTheme? {
        byId[id]
    }

    static func themes(ids: [String]) -> [JournalTheme] {
        ids.compactMap { byId[$0] }
    }

    /// Keep only known catalog ids, preserve order, drop duplicates, cap length.
    static func validate(_ ids: [String], max: Int = maxConfirmedThemes) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for id in ids {
            guard byId[id] != nil, !seen.contains(id) else { continue }
            seen.insert(id)
            result.append(id)
            if result.count >= max { break }
        }
        return result
    }

    static func displayNames(for ids: [String]) -> [String] {
        validate(ids).compactMap { byId[$0]?.displayName }
    }

    static func themes(in family: ThemeFamily) -> [JournalTheme] {
        all.filter { $0.family == family }
    }

    /// Map the pre-catalog free-text goals (and themes@1 vocabulary that users
    /// may have persisted) onto themes@2 ids.
    static func legacyGoalMapping(_ goal: String) -> String? {
        switch goal.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "self awareness", "self-awareness", "awareness":
            return "mindfulness"
        case "emotion mapping", "emotion", "feelings":
            return "therapy"
        case "calming control", "calm", "regulation":
            return "stress"
        case "stress relief", "stress", "relief":
            return "stress"
        case "thoughtful responses", "communication":
            return "communication"
        case "self-kindness", "self kindness", "selfkindness", "nurture":
            return "self_esteem"
        case "honesty", "truth":
            return "trust"
        case "compassion", "empathy":
            return "support"
        default:
            // Exact display-name match as a soft fallback.
            return byDisplayNameLowercased[goal.lowercased()]?.id
        }
    }

    /// Offline/keyword fallback when AFM is unavailable: score themes by token overlap.
    static func suggestFromKeywords(_ text: String, limit: Int = defaultSuggestionCount) -> [String] {
        let tokens = Set(
            text.lowercased()
                .split { !$0.isLetter }
                .map(String.init)
                .filter { $0.count >= 3 }
        )
        guard !tokens.isEmpty else { return [] }

        let scored: [(String, Int)] = all.compactMap { theme in
            var score = 0
            let name = theme.displayName.lowercased()
            if tokens.contains(name) { score += 5 }
            for synonym in theme.synonyms where tokens.contains(synonym.lowercased()) {
                score += 3
            }
            for token in tokens where name.contains(token) || token.contains(name) {
                score += 1
            }
            return score > 0 ? (theme.id, score) : nil
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0 < rhs.0
            }
            .prefix(limit)
            .map(\.0)
    }

    // MARK: - Private

    private static func theme(
        _ id: String,
        _ displayName: String,
        _ family: ThemeFamily,
        _ synonyms: [String] = []
    ) -> JournalTheme {
        JournalTheme(id: id, displayName: displayName, family: family, synonyms: synonyms)
    }
}
