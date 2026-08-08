//
//  ThemeCatalog.swift
//  MeetMemento
//
//  Product-owned, closed vocabulary of one-word journaling themes.
//  AFM theme estimation may only return IDs from this catalog.
//

import Foundation

/// A single journaling theme from the predetermined catalog.
struct JournalTheme: Identifiable, Hashable, Sendable, Codable {
    /// Stable machine id (snake_case). Never shown raw in UI.
    let id: String
    /// One-word display label shown on chips.
    let displayName: String
    /// Grouping for browse UI.
    let family: ThemeFamily
    /// Optional synonyms used for offline/keyword fallback matching.
    let synonyms: [String]
}

enum ThemeFamily: String, CaseIterable, Sendable, Codable, Identifiable {
    case awareness
    case emotion
    case calm
    case relationships
    case identity
    case growth
    case habits
    case creativity
    case meaning
    case body
    case work
    case reflection

    var id: String { rawValue }

    var title: String {
        switch self {
        case .awareness: return "Awareness"
        case .emotion: return "Emotion"
        case .calm: return "Calm"
        case .relationships: return "Relationships"
        case .identity: return "Identity"
        case .growth: return "Growth"
        case .habits: return "Habits"
        case .creativity: return "Creativity"
        case .meaning: return "Meaning"
        case .body: return "Body"
        case .work: return "Work"
        case .reflection: return "Reflection"
        }
    }
}

/// Bundled theme taxonomy. `catalogVersion` bumps when ids/labels change meaningfully.
enum ThemeCatalog {
    static let catalogVersion = "themes@1"

    /// Max themes a user may confirm (keeps the prompt lens focused).
    static let maxConfirmedThemes = 6

    /// Default number of AFM suggestions to preselect.
    static let defaultSuggestionCount = 4

    static let all: [JournalTheme] = [
        // Awareness
        theme("awareness", "Awareness", .awareness, ["mindfulness", "noticing", "presence"]),
        theme("clarity", "Clarity", .awareness, ["clear", "focus"]),
        theme("presence", "Presence", .awareness, ["here", "now", "attentiveness"]),
        theme("mindfulness", "Mindfulness", .awareness, ["meditation", "attention"]),
        theme("observation", "Observation", .awareness, ["noticing", "watching"]),
        theme("insight", "Insight", .awareness, ["realization", "understanding"]),
        theme("curiosity", "Curiosity", .awareness, ["wonder", "questions"]),
        theme("perspective", "Perspective", .awareness, ["viewpoint", "angle"]),
        theme("honesty", "Honesty", .awareness, ["truth", "candor"]),
        theme("acceptance", "Acceptance", .awareness, ["allowing", "surrender"]),

        // Emotion
        theme("emotion", "Emotion", .emotion, ["feelings", "mood"]),
        theme("feelings", "Feelings", .emotion, ["emotion", "affect"]),
        theme("mood", "Mood", .emotion, ["temper", "state"]),
        theme("joy", "Joy", .emotion, ["happiness", "delight"]),
        theme("gratitude", "Gratitude", .emotion, ["thankful", "appreciation"]),
        theme("anxiety", "Anxiety", .emotion, ["worry", "nervousness"]),
        theme("anger", "Anger", .emotion, ["frustration", "irritation"]),
        theme("sadness", "Sadness", .emotion, ["grief", "sorrow"]),
        theme("fear", "Fear", .emotion, ["scare", "dread"]),
        theme("loneliness", "Loneliness", .emotion, ["alone", "isolation"]),
        theme("shame", "Shame", .emotion, ["embarrassment", "guilt"]),
        theme("guilt", "Guilt", .emotion, ["remorse", "regret"]),
        theme("hope", "Hope", .emotion, ["optimism", "possibility"]),
        theme("love", "Love", .emotion, ["affection", "care"]),
        theme("envy", "Envy", .emotion, ["jealousy", "comparison"]),
        theme("tenderness", "Tenderness", .emotion, ["softness", "gentleness"]),
        theme("vulnerability", "Vulnerability", .emotion, ["openness", "exposure"]),
        theme("resilience", "Resilience", .emotion, ["bounceback", "strength"]),

        // Calm
        theme("calm", "Calm", .calm, ["peace", "stillness"]),
        theme("peace", "Peace", .calm, ["serenity", "quiet"]),
        theme("stress", "Stress", .calm, ["pressure", "tension"]),
        theme("relief", "Relief", .calm, ["ease", "release"]),
        theme("balance", "Balance", .calm, ["equilibrium", "stability"]),
        theme("grounding", "Grounding", .calm, ["centered", "anchored"]),
        theme("stillness", "Stillness", .calm, ["quiet", "silence"]),
        theme("breath", "Breath", .calm, ["breathing", "exhale"]),
        theme("rest", "Rest", .calm, ["recovery", "pause"]),
        theme("patience", "Patience", .calm, ["waiting", "tolerance"]),
        theme("soothing", "Soothing", .calm, ["comfort", "calming"]),
        theme("regulation", "Regulation", .calm, ["control", "composure"]),

        // Relationships
        theme("relationships", "Relationships", .relationships, ["connection", "people"]),
        theme("connection", "Connection", .relationships, ["bond", "closeness"]),
        theme("family", "Family", .relationships, ["parents", "siblings", "home"]),
        theme("friendship", "Friendship", .relationships, ["friends", "companionship"]),
        theme("romance", "Romance", .relationships, ["dating", "partnership", "love"]),
        theme("boundaries", "Boundaries", .relationships, ["limits", "space"]),
        theme("communication", "Communication", .relationships, ["talking", "listening"]),
        theme("trust", "Trust", .relationships, ["reliability", "faith"]),
        theme("conflict", "Conflict", .relationships, ["disagreement", "tension"]),
        theme("forgiveness", "Forgiveness", .relationships, ["lettinggo", "pardon"]),
        theme("belonging", "Belonging", .relationships, ["community", "inclusion"]),
        theme("attachment", "Attachment", .relationships, ["bonding", "dependence"]),
        theme("empathy", "Empathy", .relationships, ["compassion", "understanding"]),
        theme("compassion", "Compassion", .relationships, ["kindness", "care"]),
        theme("intimacy", "Intimacy", .relationships, ["closeness", "depth"]),
        theme("community", "Community", .relationships, ["group", "together"]),

        // Identity
        theme("identity", "Identity", .identity, ["self", "whoami"]),
        theme("selfhood", "Selfhood", .identity, ["self", "being"]),
        theme("confidence", "Confidence", .identity, ["selfesteem", "assurance"]),
        theme("worth", "Worth", .identity, ["value", "deserving"]),
        theme("authenticity", "Authenticity", .identity, ["real", "genuine"]),
        theme("values", "Values", .identity, ["principles", "beliefs"]),
        theme("purpose", "Purpose", .identity, ["meaning", "why"]),
        theme("direction", "Direction", .identity, ["path", "course"]),
        theme("independence", "Independence", .identity, ["autonomy", "selfreliance"]),
        theme("autonomy", "Autonomy", .identity, ["agency", "choice"]),
        theme("image", "Image", .identity, ["appearance", "presentation"]),
        theme("integrity", "Integrity", .identity, ["character", "ethics"]),

        // Growth
        theme("growth", "Growth", .growth, ["development", "progress"]),
        theme("healing", "Healing", .growth, ["recovery", "mending"]),
        theme("change", "Change", .growth, ["transition", "shift"]),
        theme("courage", "Courage", .growth, ["bravery", "nerve"]),
        theme("discipline", "Discipline", .growth, ["consistency", "will"]),
        theme("learning", "Learning", .growth, ["study", "skill"]),
        theme("habits", "Habits", .growth, ["routines", "patterns"]),
        theme("progress", "Progress", .growth, ["improvement", "momentum"]),
        theme("setbacks", "Setbacks", .growth, ["failure", "relapse"]),
        theme("motivation", "Motivation", .growth, ["drive", "ambition"]),
        theme("ambition", "Ambition", .growth, ["drive", "aspiration"]),
        theme("mastery", "Mastery", .growth, ["skill", "expertise"]),
        theme("transformation", "Transformation", .growth, ["reinvention", "becoming"]),
        theme("accountability", "Accountability", .growth, ["ownership", "responsibility"]),

        // Habits / daily life
        theme("routine", "Routine", .habits, ["schedule", "daily"]),
        theme("productivity", "Productivity", .habits, ["output", "efficiency"]),
        theme("focus", "Focus", .habits, ["concentration", "attention"]),
        theme("procrastination", "Procrastination", .habits, ["delay", "avoidance"]),
        theme("consistency", "Consistency", .habits, ["steadiness", "discipline", "habit"]),
        theme("energy", "Energy", .habits, ["vitality", "drive"]),
        theme("sleep", "Sleep", .habits, ["rest", "insomnia"]),
        theme("nutrition", "Nutrition", .habits, ["food", "eating"]),
        theme("movement", "Movement", .habits, ["exercise", "activity"]),
        theme("money", "Money", .habits, ["finance", "spending"]),
        theme("time", "Time", .habits, ["schedule", "hours"]),
        theme("screens", "Screens", .habits, ["phone", "digital"]),
        theme("simplicity", "Simplicity", .habits, ["minimalism", "less"]),

        // Creativity
        theme("creativity", "Creativity", .creativity, ["making", "ideas"]),
        theme("expression", "Expression", .creativity, ["voice", "art"]),
        theme("inspiration", "Inspiration", .creativity, ["muse", "spark"]),
        theme("imagination", "Imagination", .creativity, ["fantasy", "vision"]),
        theme("play", "Play", .creativity, ["fun", "lightness"]),
        theme("wonder", "Wonder", .creativity, ["awe", "marvel"]),
        theme("artistry", "Artistry", .creativity, ["craft", "making"]),
        theme("story", "Story", .creativity, ["narrative", "writing", "storytelling"]),

        // Meaning
        theme("meaning", "Meaning", .meaning, ["significance", "purpose"]),
        theme("spirituality", "Spirituality", .meaning, ["faith", "spirit"]),
        theme("faith", "Faith", .meaning, ["belief", "trust"]),
        theme("awe", "Awe", .meaning, ["wonder", "reverence"]),
        theme("mortality", "Mortality", .meaning, ["death", "impermanence"]),
        theme("legacy", "Legacy", .meaning, ["impact", "remembrance"]),
        theme("service", "Service", .meaning, ["giving", "contribution"]),
        theme("justice", "Justice", .meaning, ["fairness", "ethics"]),
        theme("nature", "Nature", .meaning, ["outdoors", "earth"]),
        theme("beauty", "Beauty", .meaning, ["aesthetics", "loveliness"]),

        // Body
        theme("body", "Body", .body, ["physical", "somatic"]),
        theme("health", "Health", .body, ["wellness", "illness"]),
        theme("pain", "Pain", .body, ["ache", "hurt"]),
        theme("embodiment", "Embodiment", .body, ["somatic", "felt"]),
        theme("sensuality", "Sensuality", .body, ["senses", "touch"]),
        theme("vitality", "Vitality", .body, ["aliveness", "vigor"]),

        // Work
        theme("work", "Work", .work, ["job", "career"]),
        theme("career", "Career", .work, ["profession", "path"]),
        theme("leadership", "Leadership", .work, ["management", "influence"]),
        theme("burnout", "Burnout", .work, ["exhaustion", "overload"]),
        theme("drive", "Drive", .work, ["hunger", "push", "ambition"]),
        theme("collaboration", "Collaboration", .work, ["teamwork", "partners"]),
        theme("performance", "Performance", .work, ["results", "delivery"]),
        theme("calling", "Calling", .work, ["vocation", "mission"]),

        // Reflection / journaling practice
        theme("reflection", "Reflection", .reflection, ["review", "lookingback"]),
        theme("memory", "Memory", .reflection, ["recollection", "past"]),
        theme("patterns", "Patterns", .reflection, ["cycles", "recurrence"]),
        theme("triggers", "Triggers", .reflection, ["activators", "cues"]),
        theme("decisions", "Decisions", .reflection, ["choices", "options"]),
        theme("intentions", "Intentions", .reflection, ["aims", "goals"]),
        theme("goals", "Goals", .reflection, ["aims", "targets"]),
        theme("priorities", "Priorities", .reflection, ["importance", "focus"]),
        theme("appreciation", "Appreciation", .reflection, ["thanks", "gratitude", "noticing"]),
        theme("celebration", "Celebration", .reflection, ["wins", "milestones"]),
        theme("grief", "Grief", .reflection, ["loss", "mourning"]),
        theme("closure", "Closure", .reflection, ["ending", "resolution"]),
        theme("beginnings", "Beginnings", .reflection, ["start", "new"]),
        theme("transitions", "Transitions", .reflection, ["change", "inbetween"]),
        theme("uncertainty", "Uncertainty", .reflection, ["unknown", "ambiguity"]),
        theme("control", "Control", .reflection, ["agency", "grip"]),
        theme("freedom", "Freedom", .reflection, ["liberation", "release"]),
        theme("kindness", "Kindness", .reflection, ["gentleness", "care"]),
        theme("nurture", "Nurture", .reflection, ["selfkindness", "selfcompassion", "gentleness"]),
        theme("bravery", "Bravery", .reflection, ["courage", "nerve", "boldness"]),
        theme("truth", "Truth", .reflection, ["honesty", "realness"]),
        theme("silence", "Silence", .reflection, ["quiet", "space"]),
        theme("listening", "Listening", .reflection, ["hearing", "attunement"]),
        theme("writing", "Writing", .reflection, ["journaling", "words"]),
        theme("voice", "Voice", .reflection, ["expression", "speak"]),
        theme("home", "Home", .reflection, ["place", "belonging"]),
        theme("travel", "Travel", .reflection, ["journey", "movement"]),
        theme("seasons", "Seasons", .reflection, ["cycles", "time", "seasonality"]),
        theme("aging", "Aging", .reflection, ["time", "maturity"]),
        theme("parenting", "Parenting", .reflection, ["children", "raising"]),
        theme("childhood", "Childhood", .reflection, ["past", "origin"]),
        theme("dreams", "Dreams", .reflection, ["aspirations", "sleep"]),
        theme("future", "Future", .reflection, ["tomorrow", "ahead"]),
        theme("past", "Past", .reflection, ["history", "memory"]),
        theme("present", "Present", .reflection, ["now", "here"]),
        theme("solitude", "Solitude", .reflection, ["alone", "quiet"]),
        theme("ritual", "Ritual", .reflection, ["practice", "ceremony"]),
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

    /// Map the pre-catalog free-text goals onto theme ids.
    static func legacyGoalMapping(_ goal: String) -> String? {
        switch goal.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "self awareness", "self-awareness", "awareness":
            return "awareness"
        case "emotion mapping", "emotion", "feelings":
            return "emotion"
        case "calming control", "calm", "regulation":
            return "regulation"
        case "stress relief", "stress", "relief":
            return "stress"
        case "thoughtful responses", "communication":
            return "communication"
        case "self-kindness", "self kindness", "selfkindness", "nurture":
            return "nurture"
        case "honesty", "truth":
            return "honesty"
        case "compassion", "empathy":
            return "compassion"
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
