import XCTest
@testable import withMemento

/// A suggestion card that cannot hold a conversation is worse than no card.
///
/// This is the regression that already shipped once. The old archive-query
/// starters ("How many times have I written about sleep?", "When did I last…")
/// all matched `TurnClassifier.quantitativePatterns`, which is checked *before*
/// `journalQuery`. Every one routed to `ReplyChannel.statistic`, where
/// `requiresOnDeviceModel` is false: the reply is a Swift-computed number with
/// an empty body and the model never runs. Three cards inviting a conversation,
/// none of which could hold one.
///
/// `DeepPromptBuilder` writes questions about the archive, so it is exactly the
/// place that failure comes back. These tests walk every prompt the builder can
/// emit and prove each one reaches the channel that actually reads entries.
final class DeepPromptRoutingTests: XCTestCase {

    // MARK: - Corpus

    /// Entries dense enough to produce people, places and clusters above
    /// `InsightEngine.lowConfidenceThreshold`.
    private func corpus(now: Date = Date()) -> [Entry] {
        let day: TimeInterval = 60 * 60 * 24
        let bodies = [
            "Work ran long again. Maya stayed late with me at the Brooklyn office.",
            "Another late one at work. Maya said the deadline had moved again.",
            "Work has been relentless. Met Maya in Brooklyn after, which helped.",
            "Deadline week at work. Maya covered for me. Brooklyn was quiet.",
            "Work eased a little today. Maya and I walked around Brooklyn.",
            "Slept badly, thinking about work. Maya texted from Brooklyn.",
            "Work felt manageable. Maya came by. Brooklyn in the rain.",
            "The work deadline landed. Maya was there. Brooklyn again."
        ]
        return bodies.enumerated().map { index, text in
            Entry(
                title: "Entry \(index + 1)",
                text: text,
                createdAt: now.addingTimeInterval(-day * Double(bodies.count - index))
            )
        }
    }

    /// Synthetic facts, one per template branch.
    ///
    /// **Not** derived from `corpus()` via `InsightEngine.facts`, and that is
    /// deliberate. Person and place facts come from `NLTagger`'s `.nameType`
    /// scheme, whose model is **not installed in the iOS Simulator**: there
    /// every word tags as `Other`, `namedEntityFacts` returns nothing, and a
    /// corpus-driven test of these templates would iterate an empty array and
    /// pass without evaluating a single prompt. Measured 2026-09-21 — the
    /// simulator produced cadence facts only. Cluster facts have the same
    /// problem for a different reason: they need cached embeddings.
    ///
    /// So the cards under test are built from facts directly. `corpus()` still
    /// backs the thin-journal and end-to-end checks below.
    private func syntheticCards() -> [ChatSuggestion] {
        let window = DateInterval(start: Date().addingTimeInterval(-86400 * 30), duration: 86400 * 30)
        let facts: [InsightFact] = [
            InsightFact(kind: .cluster, label: "work · deadline", value: "6", n: 6,
                        window: window, supportingEntryIDs: []),
            InsightFact(kind: .person, label: "Maya", value: "5", n: 5,
                        window: window, supportingEntryIDs: []),
            InsightFact(kind: .place, label: "Brooklyn", value: "4", n: 4,
                        window: window, supportingEntryIDs: []),
            InsightFact(kind: .valenceTrend, label: "Valence dipped", value: "-0.30", n: 6,
                        window: window, supportingEntryIDs: [])
        ]
        let cards = DeepPromptBuilder.prompts(from: facts, limit: 10)
        XCTAssertEqual(cards.count, 4, "a template branch stopped producing a card")
        return cards
    }

    /// Every seed the builder can emit, from all four branches.
    private func allCandidateSeeds() -> [String] {
        syntheticCards().map(\.seed)
            + DeepPromptBuilder.prompts(entries: corpus(), limit: 10).map(\.seed)
    }

    // MARK: - The guard

    func test_everySeedRoutesToTheChannelThatReadsEntries() {
        for seed in allCandidateSeeds() {
            let turn = TurnClassifier.classify(seed, hasHistory: false)
            XCTAssertEqual(
                turn, .journalQuery,
                "a deep prompt did not classify as a journal question: \(seed)"
            )

            let channel = ReplyChannel.resolve(turn: turn, hasImages: false)
            XCTAssertEqual(
                channel, .notebook,
                "a deep prompt routed to \(channel) instead of notebook: \(seed)"
            )
            XCTAssertTrue(
                channel.requiresOnDeviceModel,
                "a deep prompt landed on a channel that never runs the model: \(seed)"
            )
            XCTAssertTrue(
                channel.allowsRetrieval,
                "a deep prompt landed on a channel that never reads entries: \(seed)"
            )
        }
    }

    /// The specific shapes that caused the original outage, asserted directly
    /// so the failure message names the cause rather than a channel mismatch.
    func test_noSeedIsCountingShaped() {
        for seed in allCandidateSeeds() {
            XCTAssertNotEqual(
                TurnClassifier.classify(seed, hasHistory: false), .quantitative,
                "a deep prompt is counting-shaped and will answer with an empty body: \(seed)"
            )
        }
    }

    /// Card faces are topics in the app's voice, never the person speaking —
    /// the same rule the opener cards are held to.
    func test_cardFacesAreNotFirstPerson() {
        for card in syntheticCards() {
            let lower = card.label.lowercased()
            for opening in ["i ", "i'", "my ", "me "] {
                XCTAssertFalse(lower.hasPrefix(opening),
                               "card face is written as the person speaking: \(card.label)")
            }
        }
    }

    /// Every analysis card must carry the bubble text; the transcript has
    /// nothing else to show.
    func test_analysisCardsAlwaysCarryPromptText() {
        for card in syntheticCards() {
            XCTAssertEqual(card.kind, .analysis)
            XCTAssertFalse(
                (card.promptText ?? "").isEmpty,
                "an analysis card has no question to show: \(card.label)"
            )
        }
    }

    /// The bubble text is what the person sees and may retype. It must not be
    /// counting-shaped either, or typing it back lands on the dead channel.
    func test_promptTextIsNotCountingShaped() {
        for card in syntheticCards() {
            let prompt = card.promptText ?? ""
            XCTAssertNotEqual(
                TurnClassifier.classify(prompt, hasHistory: false), .quantitative,
                "a card's visible question is counting-shaped: \(prompt)"
            )
        }
    }

    /// A low-confidence fact is captioned "too few to call a pattern" in the
    /// Patterns tab, so it must not be offered as a conversation about one.
    func test_lowConfidenceFactsMakeNoCard() {
        let window = DateInterval(start: Date().addingTimeInterval(-86400 * 7), duration: 86400 * 7)
        let thin = InsightFact(
            kind: .person, label: "Maya", value: "2",
            n: DeepPromptBuilder.minimumSupportingEntries - 1,
            window: window, supportingEntryIDs: []
        )
        XCTAssertTrue(DeepPromptBuilder.prompts(from: [thin]).isEmpty)
    }

    /// Counting-shaped kinds are skipped by design, not by omission.
    func test_cadenceFactsMakeNoCard() {
        let window = DateInterval(start: Date().addingTimeInterval(-86400 * 7), duration: 86400 * 7)
        let cadence = InsightFact(kind: .cadence, label: "Streak", value: "8 days", n: 8,
                                  window: window, supportingEntryIDs: [])
        XCTAssertTrue(DeepPromptBuilder.prompts(from: [cadence]).isEmpty,
                      "a cadence fact became a card and will answer with an empty body")
    }

    // MARK: - The thin-journal gate

    /// A new archive has nothing to analyse. Returning `[]` is what makes the
    /// caller fall back to the opener cards that ask the person a question.
    func test_thinJournalProducesNoCards() {
        let entries = [
            Entry(title: "First", text: "Started writing today.", createdAt: Date()),
            Entry(title: "Second", text: "A quiet one.", createdAt: Date())
        ]
        XCTAssertTrue(
            DeepPromptBuilder.prompts(entries: entries).isEmpty,
            "cards were offered for an archive too thin to read"
        )
    }

    func test_emptyJournalProducesNoCards() {
        XCTAssertTrue(DeepPromptBuilder.prompts(entries: []).isEmpty)
    }

    // MARK: - Label handling

    func test_vagueClusterLabelMakesNoCard() {
        // `clusterLabel`'s own fallback names nothing, so it cannot be a topic.
        XCTAssertNil(DeepPromptBuilder.clusterTopic("Related entries"))
        XCTAssertNil(DeepPromptBuilder.clusterTopic(""))
    }

    func test_clusterTopicReadsAsProse() {
        XCTAssertEqual(DeepPromptBuilder.clusterTopic("work"), "work")
        XCTAssertEqual(DeepPromptBuilder.clusterTopic("work · deadline"), "work and deadline")
    }
}
