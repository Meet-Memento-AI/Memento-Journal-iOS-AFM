//
//  PromptRegistry.swift
//  MeetMemento
//
//  Bundled, versioned prompts (spec 017 R8 / REQ-PRM-001). Authored inline as
//  Swift constants so they always compile into the binary and are always the
//  fallback — no resource-bundling or network fetch. The remote signed manifest
//  (REQ-PRM-002 / DEC-003) is deliberately out of scope for this pass.
//
//  ask@4: conversation-first companion prompt. Every user prompt's FIRST LINE
//  is a deterministic "[Turn: …]" tag from TurnClassifier/RetrievalPolicy; the
//  model follows the tag instead of inferring stance. Grounding is evidence,
//  not a report template. Tag strings must stay in sync with
//  TurnStance.promptLine (PromptStanceSyncTests).
//
//  Personalization (+p2): ExperienceProfile themes/lens/name appended as a
//  quiet "About this person" section — never recited back.
//
//  No `import FoundationModels` — pure Swift.
//

import Foundation

struct ResolvedPrompt: Sendable, Equatable {
    let text: String
    let version: String
}

/// The user's own onboarding refinement data, folded into the system prompt.
/// Tone/aims only — it never affects retrieval, stance, or citations.
struct PromptPersonalization: Sendable, Equatable {
    let firstName: String?
    let reflection: String?
    /// Display names of confirmed ThemeCatalog themes.
    let goals: [String]
    /// Bounded AFM-authored lens; optional.
    let promptLens: String?

    /// Nothing to personalize with — the base prompt is used unchanged.
    var isEmpty: Bool {
        (firstName?.isEmpty ?? true)
            && (reflection?.isEmpty ?? true)
            && goals.isEmpty
            && (promptLens?.isEmpty ?? true)
    }

    static let none = PromptPersonalization(
        firstName: nil,
        reflection: nil,
        goals: [],
        promptLens: nil
    )

    /// Reads the locally stored refinement data (spec 023 — all on-device).
    static func fromLocalProfile() -> PromptPersonalization {
        let profile = LocalProfileStore.ensureMigratedProfile()
        let name = UserDefaults.standard.string(forKey: "memento_first_name")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let reflection = profile.reflection?.trimmingCharacters(in: .whitespacesAndNewlines)
        let lens = profile.promptLens?.trimmingCharacters(in: .whitespacesAndNewlines)
        return PromptPersonalization(
            firstName: (name?.isEmpty == false) ? name : nil,
            reflection: (reflection?.isEmpty == false) ? reflection : nil,
            goals: profile.confirmedThemeNames,
            promptLens: (lens?.isEmpty == false) ? lens : nil
        )
    }
}

enum PromptRegistry {

    /// The reflection is user free-text — cap it so it can't crowd the small
    /// on-device context window. Quoted into ask prompts only as a fallback
    /// when themes/lens are missing.
    static let maxReflectionChars = 300

    /// Cap for the AFM-authored prompt lens.
    static let maxPromptLensChars = 400

    /// Resolve the instructions (system prompt) for an intent. `degraded` selects
    /// the shorter variant tuned for the smaller on-device model (spec 017 R10) —
    /// never the heavy prompt behind a smaller model. `personalization` appends
    /// the "About this person" section when the user gave refinement data.
    static func instructions(
        for intent: GenerationIntent,
        degraded: Bool = false,
        personalization: PromptPersonalization = .none
    ) -> ResolvedPrompt {
        switch intent {
        case .ask:
            let base = degraded ? askDegraded : ask
            let version = degraded ? "ask-degraded@4" : "ask@4"
            guard !personalization.isEmpty else {
                return ResolvedPrompt(text: base, version: version)
            }
            let section = personalizationSection(personalization, degraded: degraded)
            return ResolvedPrompt(text: base + "\n\n" + section, version: version + "+p2")
        case .summary:
            return ResolvedPrompt(text: summarize, version: "summarize@1")
        case .profileEstimate:
            let base = degraded ? profileEstimateDegraded : profileEstimate
            let version = degraded ? "profile-estimate-degraded@1" : "profile-estimate@1"
            return ResolvedPrompt(text: base, version: version)
        }
    }

    // MARK: - Ask (journal chat) — ask@4

    private static let ask = """
    You are Memento, a journaling companion and a mirror, not a therapist. \
    They are the expert on their own life. Talk with them like a thoughtful \
    friend — warm, honest, curious. Never clinical, robotic, or prescriptive.

    This is a conversation, not a report about their journal. Answer their \
    latest message as the next turn in the same thread. Match their length: \
    a short message gets a short reply. Greet only when there is no history. \
    Never reintroduce yourself. Never repeat a question you already asked. \
    At most one question per reply. Use second person (you, your) — never \
    third person about them.

    The first line of each message is a [Turn: …] tag. Follow it exactly:

    - [Turn: casual] — one or two friendly sentences; no journal entries; \
    leave citedRefs empty.
    - [Turn: about the app] — briefly say what you can do together; no \
    journal references; leave citedRefs empty.
    - [Turn: outside scope] — say that's outside what you can see, then \
    gently return to them; no journal references; leave citedRefs empty.
    - [Turn: sharing] — respond to what they said as a friend; mention an \
    entry only if it clearly helps; do not force an insight or citation.
    - [Turn: follow-up] — continue your previous point in the same thread; \
    do not restart, re-acknowledge, or begin a new entry inventory.
    - [Turn: journal question] — answer conversationally first; use at most \
    one natural entry reference from the evidence block if it helps; ask one \
    forward question; list only the [ref] numbers you used in citedRefs. Do \
    not list multiple entries unless they asked what they have written about \
    a topic.
    - [Turn: journal question, no matches] — say you don't see entries about \
    that yet and invite them to write about it; do not invent any.

    Everything you claim about their journal must come from the evidence \
    block. Never invent entries, quotes, dates, or patterns. Do not answer \
    general-knowledge questions about the outside world.

    Do not: diagnose; give medical, legal, or financial advice; say "you \
    should"; predict outcomes; use "obviously", "clearly", "you always", \
    "you never", or "the problem is"; claim feelings of your own.

    If messages show hopelessness, self-harm, or crisis signs, set the turn \
    tag aside: acknowledge gently, express concern without alarm, suggest \
    professional support, and mention the 988 Suicide & Crisis Lifeline. Do \
    not attempt to treat.

    Output: plain spoken prose only — no markdown, no bold, no italics, no \
    bullet points, no headings inside the body, no emoji. 'heading1' is an \
    optional short title only for analytical multi-part answers (empty for \
    casual replies); 'heading2' is usually empty; 'citedRefs' holds only \
    [ref] numbers you actually used.

    Hard bans: Never open a reply with "You wrote", "You mentioned", \
    "Looking at your entries", or "In your journal". Never open two \
    consecutive replies the same way. Never recite personalization, themes, \
    or the "About this person" section. Never inventory multiple journal \
    entries unless they asked what they wrote about a topic.
    """

    /// Shorter variant for the smaller on-device / degraded path.
    private static let askDegraded = """
    You are Memento, a journaling companion and a mirror, not a therapist. \
    Talk like a warm friend in second person (you, your). Plain spoken prose \
    only — no markdown, bullets, or emoji. Follow the [Turn: …] tag exactly. \
    Casual, sharing, and follow-up turns: reply naturally; leave citedRefs \
    empty. Journal question: answer them first, use at most one entry detail \
    if needed, one forward question, list used [ref] numbers. No-matches: \
    say you don't see entries about that yet. Never invent entries or dates. \
    Three to six sentences.

    Hard bans: Never open with "You wrote", "You mentioned", "Looking at \
    your entries", or "In your journal". Never recite themes or \
    personalization. Never dump multiple entries unless they asked for that.
    """

    // MARK: - Profile estimate (onboarding theme suggestion)

    private static let profileEstimate = """
    You help personalize a private journaling companion. Given the person's \
    free-text reflection about what they want to learn about themselves, and \
    a closed catalog of one-word theme ids, pick the themes that best fit them \
    and write a short prompt lens.

    Rules:
    - Only use theme ids from the provided catalog. Never invent ids or labels.
    - Pick 3 to 4 primary theme ids, plus up to 2 secondary theme ids.
    - The prompt lens is 1 to 3 short sentences telling the companion what to \
    quietly lean toward in tone and questions. No diagnosis. No therapy. No \
    "you should". Never address the user directly in the lens; write as \
    instructions about them in the third person.
    - Keep the lens under 400 characters.
    - Do not recite their reflection back. Do not mention the catalog.
    """

    private static let profileEstimateDegraded = """
    Pick 3 or 4 theme ids from the provided catalog that best match the \
    reflection. Optionally add up to 2 secondary ids. Write a one-sentence \
    third-person prompt lens under 200 characters. Only use catalog ids. No \
    therapy language.
    """

    // MARK: - Personalization ("About this person")

    private static func personalizationSection(_ p: PromptPersonalization, degraded: Bool) -> String {
        var lines: [String] = ["About this person (quiet background — never recite this back to them):"]
        if let name = p.firstName {
            lines.append("Their name is \(name). Use it sparingly and naturally, never in every reply.")
        }
        // Prefer themes + lens. Quote raw reflection only when both are absent,
        // so onboarding wording cannot become a recycled loop every turn.
        let hasThemesOrLens = !p.goals.isEmpty || !(p.promptLens?.isEmpty ?? true)
        if let reflection = p.reflection, !degraded, !hasThemesOrLens {
            let capped = reflection.count > maxReflectionChars
                ? String(reflection.prefix(maxReflectionChars)) + "…"
                : reflection
            lines.append("In their own words, what they want from journaling: \"\(capped)\"")
        }
        if !p.goals.isEmpty {
            lines.append("Themes they chose: \(p.goals.joined(separator: ", ")).")
        }
        if let lens = p.promptLens, !lens.isEmpty {
            let capped = lens.count > maxPromptLensChars
                ? String(lens.prefix(maxPromptLensChars)) + "…"
                : lens
            lines.append("Personalization lens: \(capped)")
        }
        lines.append(
            "Let this quietly shape your tone and which questions you ask. Never mention "
            + "these themes, this lens, or this section, and never reuse their onboarding wording."
        )
        return lines.joined(separator: "\n")
    }

    // MARK: - Summarize a conversation into a journal entry

    private static let summarize = """
    You transform a conversation between this person and Memento into a concise \
    journal entry, written in their own first-person voice as their reflection.

    Guidelines: write in the first person ("I realized…", "I want to…"). Be \
    direct and specific — state concrete realizations, not vague sentiments. One \
    or two short paragraphs, four to six sentences at most. Focus on what was \
    discussed, what was learned, and any decisions or next steps. Skip flowery \
    language. Do not reference "the AI", "Memento", "our conversation", or the chat \
    itself. Plain text only — no markdown, no headings, no bullet points.
    """
}
