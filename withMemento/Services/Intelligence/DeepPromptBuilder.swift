//
//  DeepPromptBuilder.swift
//  withMemento
//
//  Suggestion cards built from what the person actually wrote.
//
//  The empty state promises "Let's dive deeper into your journal". Until this
//  existed the three cards under that headline were drawn from a static string
//  pool that had never read an entry, and tapping one asked the *person* a
//  question rather than reading anything back. These cards name real topics,
//  real people and real places found in the archive, and tapping one runs
//  retrieval over it.
//

import Foundation

/// Turns `InsightEngine` facts into `.analysis` suggestion cards.
///
/// Two hard rules, both inherited from `ThemeAwareChatStarters` and both
/// enforced by tests rather than review:
///
/// 1. **Never counting-shaped.** "How many…", "How often…", "When did I last…"
///    and "how has X changed/shifted" all match
///    `TurnClassifier.quantitativePatterns`, which is checked *before*
///    `journalQuery`. A seed that matches routes to `ReplyChannel.statistic`,
///    where `requiresOnDeviceModel` is false — the reply becomes a Swift-
///    computed number with an empty body and **no model runs at all**. This
///    already shipped once. `DeepPromptRoutingTests` fails if it comes back.
/// 2. **Never advice-shaped.** The archivist persona refuses advice
///    (REQ-SUR-002, spec 019 R6), so a seed asking what to *do* buys a refusal.
///
/// Every seed therefore says "my entries" — which puts it in
/// `TurnClassifier.journalWords` *and* matches `journalPossessivePatterns` —
/// and asks what is *there*, never what to do about it.
enum DeepPromptBuilder {

    /// A fact needs this many supporting entries before it can become a card.
    ///
    /// Deliberately `InsightEngine`'s own low-confidence bar rather than a
    /// second number: a fact the Patterns tab would caption "too few to call a
    /// pattern" has no business being offered as a conversation about a
    /// pattern. This doubles as the thin-journal gate — a new archive produces
    /// no qualifying facts, `prompts` returns `[]`, and the caller falls back
    /// to the opener cards that ask the person a question instead.
    static var minimumSupportingEntries: Int { InsightEngine.lowConfidenceThreshold }

    /// Cards for `entries`, or `[]` when the archive is too thin to read.
    ///
    /// `limit` is the number of cards the empty state shows. Kinds are
    /// interleaved before truncation so three cards are three *different*
    /// registers — a topic, a person, a place — rather than three clusters.
    static func prompts(
        entries: [Entry],
        moodLabels: [UUID: [String]] = [:],
        now: Date = Date(),
        calendar: Calendar = .current,
        limit: Int = 3
    ) -> [ChatSuggestion] {
        let facts = InsightEngine.facts(
            entries: entries, now: now, calendar: calendar, moodLabels: moodLabels
        )
        return prompts(from: facts, calendar: calendar, limit: limit)
    }

    /// The fact-to-card half, split out so it can be tested directly.
    ///
    /// This seam is not incidental. Person and place facts come from
    /// `NLTagger`'s `.nameType` scheme, whose model **is not installed in the
    /// iOS Simulator** — there every word tags as `Other`, so
    /// `InsightEngine.facts` returns cadence only and an entries-based test of
    /// these templates passes without ever evaluating one. Feeding synthetic
    /// facts is what keeps the templates covered in CI.
    static func prompts(
        from facts: [InsightFact],
        calendar: Calendar = .current,
        limit: Int = 3
    ) -> [ChatSuggestion] {
        var byKind: [InsightFact.Kind: [ChatSuggestion]] = [:]
        var seenLabels: Set<String> = []

        for fact in facts {
            // `.cadence`, `.count` and `.lastMention` are skipped by design,
            // not by omission: their labels are "Streak" / "Longest gap" and
            // any prompt built from them is a counting question, which is
            // exactly the dead channel described above.
            guard Self.usableKinds.contains(fact.kind) else { continue }
            guard fact.n >= minimumSupportingEntries else { continue }
            guard let suggestion = self.suggestion(for: fact, calendar: calendar) else { continue }

            let key = suggestion.label.lowercased()
            guard seenLabels.insert(key).inserted else { continue }
            byKind[fact.kind, default: []].append(suggestion)
        }

        return interleave(byKind, limit: limit)
    }

    /// Kinds whose `label` names something a person can actually talk about.
    private static let usableKinds: Set<InsightFact.Kind> = [
        .cluster, .person, .place, .valenceTrend
    ]

    /// One card per fact, or nil when the fact's label is too vague to name.
    static func suggestion(
        for fact: InsightFact,
        calendar: Calendar
    ) -> ChatSuggestion? {
        let period = periodPhrase(for: fact.window, calendar: calendar)

        switch fact.kind {
        case .cluster:
            guard let topic = clusterTopic(fact.label) else { return nil }
            // "The thread through X" rather than "What X keeps circling back
            // to": `clusterLabel` can return two terms, and the latter reads
            // as nonsense once `topic` is "work and deadline".
            return ChatSuggestion(
                label: "The thread through \(topic)",
                seed: "Look across my entries about \(topic) \(period) and tell me what "
                    + "keeps coming up in them — the thread running through them, and "
                    + "where it shifts. Quote the entries you are drawing on.",
                themeName: "Patterns",
                kind: .analysis,
                promptText: "What keeps coming up when I write about \(topic)?"
            )

        case .person:
            let name = fact.label
            return ChatSuggestion(
                label: "How \(name) shows up in what you write",
                seed: "Look across my entries that mention \(name) \(period) and tell me "
                    + "what is actually going on there — what recurs, and what has moved. "
                    + "Quote the entries you are drawing on.",
                themeName: "People",
                kind: .analysis,
                promptText: "What do my entries say about \(name)?"
            )

        case .place:
            let name = fact.label
            return ChatSuggestion(
                label: "\(name), in your own words",
                seed: "Look across my entries that mention \(name) \(period) and tell me "
                    + "what that place seems to hold for me. Quote the entries you are "
                    + "drawing on.",
                themeName: "Places",
                kind: .analysis,
                promptText: "What do my entries say about \(name)?"
            )

        case .valenceTrend:
            // Phrased as "where the tone sits" rather than "how has my mood
            // changed": the latter matches `\bhow has (my )?.{0,40}\b(changed|
            // shifted)\b` and would route to `.statistic`.
            return ChatSuggestion(
                label: "Where the tone has been sitting",
                seed: "Look across my entries \(period) and tell me where the tone sits "
                    + "across them — what lifts it and what weighs on it. Quote the "
                    + "entries you are drawing on.",
                themeName: "Mood",
                kind: .analysis,
                promptText: "Where has the tone of my entries been sitting?"
            )

        case .cadence, .count, .lastMention:
            return nil
        }
    }

    /// `clusterLabel` returns up to two IDF-ranked terms joined by " · ", or
    /// the literal "Related entries" when it found nothing worth ranking.
    /// That fallback names nothing, so it makes no card.
    static func clusterTopic(_ label: String) -> String? {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "Related entries" else { return nil }
        let terms = trimmed
            .components(separatedBy: " · ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !terms.isEmpty else { return nil }
        return terms.count == 1 ? terms[0] : terms.prefix(2).joined(separator: " and ")
    }

    /// Names the fact's own window instead of inventing a period. A window
    /// inside one month reads "in August"; a longer one reads "since August".
    static func periodPhrase(for window: DateInterval, calendar: Calendar) -> String {
        let month = DateFormatter()
        month.calendar = calendar
        month.locale = .current
        month.setLocalizedDateFormatFromTemplate("LLLL")

        let start = month.string(from: window.start)
        let end = month.string(from: window.end)
        return start == end ? "in \(start)" : "since \(start)"
    }

    /// Round-robin across kinds so the three cards are three different
    /// registers rather than whichever kind happened to produce most facts.
    private static func interleave(
        _ byKind: [InsightFact.Kind: [ChatSuggestion]],
        limit: Int
    ) -> [ChatSuggestion] {
        // Fixed kind order keeps the result stable for a given fact set, which
        // the tests rely on and which stops the cards reshuffling on every
        // redraw of the empty state.
        let order: [InsightFact.Kind] = [.cluster, .person, .place, .valenceTrend]
        var cursors: [InsightFact.Kind: Int] = [:]
        var result: [ChatSuggestion] = []

        while result.count < limit {
            var appended = false
            for kind in order {
                guard result.count < limit else { break }
                let index = cursors[kind, default: 0]
                guard let bucket = byKind[kind], index < bucket.count else { continue }
                result.append(bucket[index])
                cursors[kind] = index + 1
                appended = true
            }
            if !appended { break }
        }
        return result
    }
}
