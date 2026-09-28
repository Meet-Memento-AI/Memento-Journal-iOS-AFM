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
        opener(card: "The week you've had",
               opens: "Let's talk about the week I've had.",
               theme: "Wellness"),
        opener(card: "Something small that went right",
               opens: "Let's talk about something small that went right.",
               theme: "Gratitude"),
        opener(card: "A thing you keep coming back to",
               opens: "Let's talk about a thing I keep coming back to.",
               theme: "Mindfulness")
    ]

    /// One opener card, with the three strings kept in step.
    static func opener(card: String, opens: String, theme: String?) -> ChatSuggestion {
        ChatSuggestion(
            label: card,
            seed: ThemeAwareChatStarters.seed(forOpening: opens),
            themeName: theme,
            kind: .opener,
            promptText: opens
        )
    }
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
            for pair in templates(for: lower, display: name) {
                pool.append(ChatSuggestion.opener(card: pair.card, opens: pair.opens, theme: name))
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
            result.append(ChatSuggestion.opener(
                card: topic, opens: opensLine(forCard: topic), theme: theme
            ))
        }
        return filled(result, limit: limit)
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
    /// One authored pair: the tile face, and the line the person's bubble shows.
    ///
    /// Both are written by hand. Deriving `opens` from `card` was tried and
    /// abandoned — a second-to-first-person transform cannot tell the noun
    /// "something" from a verb, so "Something you noticed about yourself"
    /// became "Something me noticed about myself". A rule that is wrong on
    /// 5 of 44 entries is worse than a file someone has to keep in step,
    /// because nothing tells you when it breaks on entry 45.
    struct StarterPrompt: Decodable, Hashable {
        let card: String
        let opens: String
    }

    static var genericEntries: [StarterPrompt] {
        if let url = Bundle.main.url(forResource: "AISuggestionPrompts", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let json = try? JSONDecoder().decode(PromptsFile.self, from: data),
           !json.prompts.isEmpty {
            return json.prompts
        }
        return bundledOpeners
    }

    /// Tile faces only — what the routing and phrase guards walk.
    static var genericPool: [String] { genericEntries.map(\.card) }

    /// The authored bubble line for a card, or the card itself when it did not
    /// come from the file (tests inject their own pools).
    static func opensLine(forCard card: String) -> String {
        genericEntries.first { $0.card == card }?.opens ?? card
    }

    /// Used only when the resource is missing. Kept short and in the same voice
    /// as the file — the old inline fallback was a second copy of the archive
    /// queries, so a missing resource silently restored the behaviour the file
    /// was re-authored to remove.
    private static let bundledOpeners: [StarterPrompt] = [
        .init(card: "The week you've had", opens: "Let's talk about the week I've had."),
        .init(card: "Something small that went right",
              opens: "Let's talk about something small that went right."),
        .init(card: "A thing you keep coming back to",
              opens: "Let's talk about a thing I keep coming back to."),
        .init(card: "How today actually went", opens: "Let's talk about how today actually went."),
        .init(card: "How you've been sleeping", opens: "Let's talk about how I've been sleeping."),
        .init(card: "Thinking out loud", opens: "I just want to think out loud for a bit.")
    ]

    private struct PromptsFile: Decodable {
        let prompts: [StarterPrompt]
    }

    /// Exactly `limit` cards, no two showing the same face.
    ///
    /// The empty state is a fixed three-tile layout, so "however many the
    /// archive happened to yield" is not a valid answer. Two ways it used to
    /// come up short:
    ///
    /// - `DeepPromptBuilder.interleave` stops as soon as no kind has another
    ///   fact left, so an archive with one qualifying cluster and nothing else
    ///   yields one card. `rotateSuggestions` then installed that one card over
    ///   the three openers already on screen, and two tiles vanished.
    /// - `ChatMessagesView` only fell back to openers when the list was
    ///   *empty*, so one or two cards rendered as one or two tiles.
    ///
    /// Preferred cards keep their order and win ties; `fillers` top the list up.
    /// Deduplication is by the visible label, case- and whitespace-insensitive,
    /// because two tiles reading the same thing is the defect a person sees —
    /// `id` is a fresh UUID per rotation, so it can never catch this.
    static func filled(
        _ preferred: [ChatSuggestion],
        limit: Int = 3,
        fillers: [ChatSuggestion] = ChatSuggestion.fallbackStarters
    ) -> [ChatSuggestion] {
        var result: [ChatSuggestion] = []
        var seen: Set<String> = []

        for card in preferred + fillers {
            guard result.count < limit else { break }
            let face = card.label
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !face.isEmpty, seen.insert(face).inserted else { continue }
            result.append(card)
        }
        return result
    }

    /// Turns a card's topic into the instruction the assistant opens on.
    ///
    /// The person never sees this and it is never stored as their turn — it
    /// exists only so the model has something to speak first about.
    /// What the model is asked to do once the person's bubble is on screen.
    ///
    /// The old seed said "open the conversation by asking them about this",
    /// which was right while tapping a card showed nothing: the assistant had
    /// to raise the topic because nobody else had. Now the card puts the
    /// person's line in the transcript first, so re-asking reads as if the
    /// assistant did not read it — "Let's talk about the week I've had." met
    /// with "How has your week been?".
    ///
    /// Still one question, because there is nothing in the archive to answer
    /// from: the opener path is what a thin journal falls back to.
    static func seed(forOpening opens: String) -> String {
        "They have just said: \"\(opens)\" Reply to that. Ask one question that "
            + "moves it forward. Do not ask them to raise the topic again."
    }

    /// Themed topics, in the app's voice.
    ///
    /// These used to be archive queries ("What patterns around \(lower) show up
    /// in my recent entries?"). That asks the notebook a question, which is a
    /// fine thing to be able to do but a poor way to *begin* — and on an empty
    /// or thin journal it answers with nothing. A starter's job is to get the
    /// first honest sentence out of the person; the notebook can be consulted
    /// once there is something to consult.
    private static func templates(for lower: String, display: String) -> [StarterPrompt] {
        [
            .init(card: "\(display) lately",
                  opens: "Let's talk about \(lower) lately."),
            .init(card: "How \(lower) has been going",
                  opens: "Let's talk about how \(lower) has been going."),
            .init(card: "Where \(lower) is sitting right now",
                  opens: "Let's talk about where \(lower) is sitting right now."),
            .init(card: "\(display) this week",
                  opens: "Let's talk about \(lower) this week.")
        ]
    }
}
