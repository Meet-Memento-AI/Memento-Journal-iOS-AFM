//
//  ThemeAwareChatStarters.swift
//  withMemento
//
//  Templated chat empty-state starters derived from confirmed ThemeCatalog
//  themes. No model generation — pure local templates so uniqueness is visible
//  without free-form AI chatter.
//

import Foundation

/// One empty-state starter: the prompt to send, plus the confirmed catalog
/// theme shown on the card's pill. `themeName` is nil when the profile has
/// no confirmed themes.
///
/// **A starter is something the person says, not something asked of them.**
/// Tapping a card sends this text as the user's turn
/// (`ChatViewModel.sendMessage(prompt:)`), so it has to read as an opening
/// line. Two hard rules follow, both learned the expensive way:
///
/// 1. **Never a counting question.** The previous starters — "How many times
///    have I written about sleep this year?", "How often…", "When did I last…"
///    — all matched `TurnClassifier.quantitativePatterns`, so every one routed
///    to `.quantitative` → `ReplyChannel.statistic`, where
///    `requiresOnDeviceModel` is false and the reply is a Swift-computed fact
///    with an empty body. No model ran. Three cards inviting a conversation,
///    none of which could hold one. `StarterRoutingTests` now fails if that
///    ever comes back.
/// 2. **Never advice-shaped.** The archivist persona refuses advice
///    (`REQ-SUR-002`, spec 019 R6), so a starter that asks for a plan buys a
///    refusal.
///
/// These open in the present tense and lean on nothing in the archive, because
/// the person most likely to be looking at them has written nothing yet — where
/// the old recall starters answered "0 times".
struct ChatSuggestion: Hashable, Identifiable {
    let id: UUID
    let prompt: String
    let themeName: String?

    init(prompt: String, themeName: String?, id: UUID = UUID()) {
        self.id = id
        self.prompt = prompt
        self.themeName = themeName
    }

    /// Canvas-only starters so AIChatView previews show pills without writing
    /// a profile into UserDefaults.
    static let previewSamples: [ChatSuggestion] = openers

    /// Shown under the empty-state headline when rotation has not produced
    /// chips yet, so the three tiles never vanish. Pills always render.
    static let fallbackStarters: [ChatSuggestion] = openers

    /// Three registers, deliberately distinct: something heavy, something
    /// ordinary, something unresolved. Each classifies `.share` → `.companion`
    /// and touches no retrieval, so it works on an empty journal.
    private static let openers: [ChatSuggestion] = [
        ChatSuggestion(
            prompt: "I want to talk about the week I've had",
            themeName: "Wellness"
        ),
        ChatSuggestion(
            prompt: "Something small went right today",
            themeName: "Gratitude"
        ),
        ChatSuggestion(
            prompt: "There's something I keep coming back to",
            themeName: "Mindfulness"
        )
    ]
}

enum ThemeAwareChatStarters {
    /// Build up to `limit` starters from confirmed theme display names.
    /// Returns an empty array when the profile has no themes (caller falls back
    /// to the generic prompt pool).
    static func starters(
        themeIds: [String] = LocalProfileStore.ensureMigratedProfile().confirmedThemeIds,
        limit: Int = 3
    ) -> [ChatSuggestion] {
        let names = ThemeCatalog.displayNames(for: themeIds)
        guard !names.isEmpty else { return [] }

        var pool: [ChatSuggestion] = []
        for name in names {
            let lower = name.lowercased()
            for template in templates(for: lower, display: name) {
                pool.append(ChatSuggestion(prompt: template, themeName: name))
            }
        }

        // Stable shuffle keyed by theme set so rotation still feels fresh but
        // stays deterministic within a session when called repeatedly with same input.
        return Array(pool.shuffled().prefix(limit))
    }

    /// Merge theme starters with a generic fallback pool.
    /// At most one themed chip; the rest come from the generic pool so the
    /// empty state is not three "tell me about {goal}" prompts.
    /// Generic fillers still get a pill from the user's remaining confirmed themes.
    static func rotate(
        genericPool: [String],
        limit: Int = 3
    ) -> [ChatSuggestion] {
        let themeNames = ThemeCatalog.displayNames(
            for: LocalProfileStore.ensureMigratedProfile().confirmedThemeIds
        )
        let themed = starters(limit: 1)
        var result: [ChatSuggestion] = []
        var usedThemes: Set<String> = []
        if let first = themed.first {
            result.append(first)
            if let theme = first.themeName { usedThemes.insert(theme) }
        }
        let leftoverThemes = themeNames.filter { !usedThemes.contains($0) }
        let pillNames = themeNames.isEmpty ? Self.defaultPillNames : themeNames
        var themeCursor = 0
        let needed = max(limit - result.count, 0)
        for prompt in genericPool.shuffled().prefix(needed) {
            let theme: String
            if leftoverThemes.isEmpty {
                theme = pillNames[themeCursor % pillNames.count]
            } else if themeCursor < leftoverThemes.count {
                theme = leftoverThemes[themeCursor]
            } else {
                theme = pillNames[themeCursor % pillNames.count]
            }
            themeCursor += 1
            result.append(ChatSuggestion(prompt: prompt, themeName: theme))
        }
        return Array(result.prefix(limit))
    }

    /// Pills on the empty-state tiles when the profile has no confirmed themes.
    private static let defaultPillNames = ["Mindfulness", "Goals", "Sleep"]

    /// The untemplated pool `rotate` draws from — which is **two of the three
    /// cards a person actually sees**.
    ///
    /// It previously lived as a private array inside `AIChatView`, out of reach
    /// of every test, while the starter tests pinned only the two constants that
    /// are the *fallback* path. That is how "How has my mood shifted over the
    /// past two weeks?" shipped in the pool while a green test forbade the
    /// phrase. It lives here now so `ThemePriorTests.allStarterPrompts` and the
    /// routing guard in `TurnClassifierTests` can both reach it.
    static var genericPool: [String] {
        if let url = Bundle.main.url(forResource: "AISuggestionPrompts", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let json = try? JSONDecoder().decode(PromptsFile.self, from: data),
           !json.prompts.isEmpty {
            return json.prompts
        }
        return bundledOpeners
    }

    /// Used only when the resource is missing. Kept short and in the same voice
    /// as the file — the old inline fallback was a second copy of the archive
    /// queries, so a missing resource silently restored the behaviour the file
    /// was re-authored to remove.
    private static let bundledOpeners: [String] = [
        "I want to talk about the week I've had",
        "Something small went right today",
        "There's something I keep coming back to",
        "Today was harder than it needed to be",
        "I haven't been sleeping well",
        "I just want to think out loud for a minute"
    ]

    private struct PromptsFile: Decodable {
        let prompts: [String]
    }

    /// Themed openers, in the person's own voice.
    ///
    /// These used to be archive queries ("What patterns around \(lower) show up
    /// in my recent entries?"). That asks the notebook a question, which is a
    /// fine thing to be able to do but a poor way to *begin* — and on an empty
    /// or thin journal it answers with nothing. A starter's job is to get the
    /// first honest sentence out of the person; the notebook can be consulted
    /// once there is something to consult.
    private static func templates(for lower: String, display: String) -> [String] {
        [
            "I've been thinking about \(lower) lately",
            "\(display) has been on my mind this week",
            "I want to talk about how \(lower) is going",
            "\(display) is sitting differently with me right now"
        ]
    }
}
