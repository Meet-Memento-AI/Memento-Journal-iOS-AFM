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
/// **A starter is a topic, never words put in the person's mouth.**
///
/// `label` is the card face and `seed` is what the assistant is asked to open
/// on. Nothing here is ever appended as the person's turn. That distinction is
/// load-bearing rather than stylistic: `ChatService.summarizeChat` maps the
/// on-screen messages to `ChatTurn`s by `isFromUser` and hands them to
/// `summarizeConversation`, which writes a journal entry. A starter posted as a
/// user bubble would be summarised back into the person's own journal as
/// something they said. They did not say it.
///
/// Two more rules, both learned the expensive way:
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
/// What tapping a card is supposed to do.
///
/// The two kinds differ in who speaks first, which is why they cannot share a
/// code path:
///
/// - `.opener` — the archive is thin or the person is new. The assistant asks
///   *them* a question and nothing is shown as having been asked. This is the
///   original behaviour and everything documented above applies to it.
/// - `.analysis` — the archive has enough in it to be read. The card carries a
///   real question about the journal, that question is shown in the transcript
///   as `promptText`, and the answer comes back grounded in retrieved entries.
///
/// An `.analysis` seed must classify as `TurnType.journalQuery` so it routes to
/// `ReplyChannel.notebook` — the only channel that both retrieves and runs the
/// model. `DeepPromptRoutingTests` fails if one ever routes to `.quantitative`.
enum ChatSuggestionKind: Hashable {
    case opener
    case analysis
}

struct ChatSuggestion: Hashable, Identifiable {
    let id: UUID
    /// The card face. A topic, in the app's voice — never first person.
    let label: String
    /// What the assistant is asked to open on. Never shown, never stored as a
    /// turn by the person.
    let seed: String
    let themeName: String?
    let kind: ChatSuggestionKind
    /// For `.analysis` only: the question shown in the transcript as the turn
    /// that started the conversation. Nil for `.opener`, which shows nothing.
    ///
    /// This is deliberately not the `seed`. The seed is an instruction written
    /// for the model and reads like one; this is the same question written for
    /// a person to read back.
    let promptText: String?

    init(
        label: String,
        seed: String,
        themeName: String?,
        kind: ChatSuggestionKind = .opener,
        promptText: String? = nil,
        id: UUID = UUID()
    ) {
        self.id = id
        self.label = label
        self.seed = seed
        self.themeName = themeName
        self.kind = kind
        self.promptText = promptText
    }

    /// Canvas-only starters so AIChatView previews show pills without writing
    /// a profile into UserDefaults.
    static let previewSamples: [ChatSuggestion] = openers

    /// Shown under the empty-state headline when rotation has not produced
    /// chips yet, so the three tiles never vanish. Pills always render.
    static let fallbackStarters: [ChatSuggestion] = openers

    /// Three registers, deliberately distinct: something heavy, something
    /// ordinary, something unresolved. None leans on the archive, because the
    /// person looking at the empty state has most likely written nothing — which
    /// is where the old recall starters answered "0 times".
    private static let openers: [ChatSuggestion] = [
        ChatSuggestion(
            label: "The week you've had",
            seed: "Open the conversation by asking how their week has actually been.",
            themeName: "Wellness"
        ),
        ChatSuggestion(
            label: "Something small that went right",
            seed: "Open the conversation by asking about one small thing that went right today.",
            themeName: "Gratitude"
        ),
        ChatSuggestion(
            label: "A thing you keep coming back to",
            seed: "Open the conversation by asking what keeps returning to them lately.",
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
            for topic in templates(for: lower, display: name) {
                pool.append(ChatSuggestion(
                    label: topic,
                    seed: Self.seed(forTopic: topic),
                    themeName: name
                ))
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
        for topic in genericPool.shuffled().prefix(needed) {
            let theme: String
            if leftoverThemes.isEmpty {
                theme = pillNames[themeCursor % pillNames.count]
            } else if themeCursor < leftoverThemes.count {
                theme = leftoverThemes[themeCursor]
            } else {
                theme = pillNames[themeCursor % pillNames.count]
            }
            themeCursor += 1
            result.append(ChatSuggestion(
                label: topic,
                seed: Self.seed(forTopic: topic),
                themeName: theme
            ))
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
        "The week you've had",
        "Something small that went right",
        "A thing you keep coming back to",
        "How today actually went",
        "How you've been sleeping",
        "Thinking out loud"
    ]

    private struct PromptsFile: Decodable {
        let prompts: [String]
    }

    /// Turns a card's topic into the instruction the assistant opens on.
    ///
    /// The person never sees this and it is never stored as their turn — it
    /// exists only so the model has something to speak first about.
    static func seed(forTopic topic: String) -> String {
        "Open the conversation by asking them about this, in one question: \(topic)."
    }

    /// Themed topics, in the app's voice.
    ///
    /// These used to be archive queries ("What patterns around \(lower) show up
    /// in my recent entries?"). That asks the notebook a question, which is a
    /// fine thing to be able to do but a poor way to *begin* — and on an empty
    /// or thin journal it answers with nothing. A starter's job is to get the
    /// first honest sentence out of the person; the notebook can be consulted
    /// once there is something to consult.
    private static func templates(for lower: String, display: String) -> [String] {
        [
            "\(display) lately",
            "How \(lower) has been going",
            "Where \(lower) is sitting right now",
            "\(display) this week"
        ]
    }
}
