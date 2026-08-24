import XCTest
@testable import MeetMemento

/// Confidence-bar behavior. `semanticThreshold` is pure math and always
/// deterministic; the retrieve() cases use gibberish/distinct tokens so the
/// keyword path decides even where NLEmbedding is unavailable (CI).
final class EntryRetrieverConfidenceTests: XCTestCase {

    // MARK: - semanticThreshold (pure)

    func test_smallCorpus_usesRaisedAbsoluteFloor() {
        let t = EntryRetriever.semanticThreshold(cosines: [0.9, 0.9], highBar: false)
        XCTAssertEqual(t, RetrieverTuning.default.semanticFloorAbs + 0.05, accuracy: 0.0001)
    }

    func test_flatCorpus_nothingClearsSigma() {
        // Identical cosines: σ = 0 → threshold = max(floor, μ). All values equal
        // μ, so with values below the floor nothing is significant.
        let cosines = Array(repeating: 0.25, count: 10)
        let t = EntryRetriever.semanticThreshold(cosines: cosines, highBar: false)
        XCTAssertEqual(t, RetrieverTuning.default.semanticFloorAbs, accuracy: 0.0001)
        XCTAssertTrue(cosines.allSatisfy { $0 < t })
    }

    func test_outlierClearsThreshold_bulkDoesNot() {
        var cosines = Array(repeating: 0.30, count: 9)
        cosines.append(0.75)
        let t = EntryRetriever.semanticThreshold(cosines: cosines, highBar: false)
        XCTAssertTrue(0.75 >= t, "the outlier should be significant")
        XCTAssertTrue(0.30 < t, "the bulk should not be")
    }

    func test_highBar_isStricter() {
        let cosines = [0.3, 0.35, 0.4, 0.45, 0.5, 0.55]
        let normal = EntryRetriever.semanticThreshold(cosines: cosines, highBar: false)
        let high = EntryRetriever.semanticThreshold(cosines: cosines, highBar: true)
        XCTAssertGreaterThan(high, normal)
    }

    // MARK: - Keyword bar via retrieve()

    private func entry(_ title: String, _ text: String, daysAgo: Double = 1) -> Entry {
        Entry(id: UUID(), title: title, text: text,
              createdAt: Date().addingTimeInterval(-daysAgo * 86_400),
              updatedAt: Date())
    }

    /// Gibberish-token corpus: embeddings (if present) can't produce hot
    /// cosines, so the keyword bar decides the signal.
    private func gibberishCorpus() -> [Entry] {
        (0..<6).map { i in
            entry("zorblat \(i)", "flumox vendrik parlune quostam entry number \(i) grebbin marzipol")
        }
    }

    func test_singleSharedWord_isNotASignal() {
        // One body-word overlap scores 1.0 < keywordSignalMin (2.0) → ambient.
        let entries = gibberishCorpus()
        let result = EntryRetriever.retrieve(
            RetrievalQuery(currentMessage: "xudlop wibble quostam"),
            entries: entries
        )
        XCTAssertTrue(result.isAmbient, "a single shared word must not ground the reply")
    }

    func test_titleAndBodyHit_isASignal() {
        // Title hit (1.5) + body hit (1.0) = 2.5 ≥ 2.0 → real match, not ambient.
        var entries = gibberishCorpus()
        entries.append(entry("marathon training", "long marathon run this morning, legs sore"))
        let result = EntryRetriever.retrieve(
            RetrievalQuery(currentMessage: "how did marathon prep go"),
            entries: entries
        )
        XCTAssertFalse(result.isAmbient)
        XCTAssertTrue(result.entries.contains { $0.text.contains("marathon") })
    }

    func test_noMatch_fallsBackToAmbient_cappedForHighBar() {
        let entries = gibberishCorpus()
        let result = EntryRetriever.retrieve(
            RetrievalQuery(currentMessage: "totally unrelated xyzzy words", highBar: true),
            entries: entries
        )
        XCTAssertTrue(result.isAmbient)
        XCTAssertLessThanOrEqual(result.entries.count, RetrieverTuning.default.ambientCapHighBar)
    }

    func test_emptyInputs_returnEmpty() {
        XCTAssertTrue(EntryRetriever.retrieve(RetrievalQuery(currentMessage: "anything"), entries: []).isEmpty)
        XCTAssertTrue(EntryRetriever.retrieve(RetrievalQuery(currentMessage: "   "), entries: gibberishCorpus()).isEmpty)
    }

    // MARK: - Cached keyword text (spec 029: no per-turn lowercasing)

    func test_retrieve_isStableAcrossRepeatedCalls() {
        // The lowercased-text and vector caches must not change what a second
        // identical call returns.
        var entries = gibberishCorpus()
        entries.append(entry("marathon training", "long marathon run this morning, legs sore"))
        let query = RetrievalQuery(currentMessage: "how did marathon prep go")
        let first = EntryRetriever.retrieve(query, entries: entries)
        let second = EntryRetriever.retrieve(query, entries: entries)
        XCTAssertEqual(first, second)
        XCTAssertFalse(second.isAmbient)
    }

    func test_editedEntry_sameId_invalidatesCachedKeywordText() {
        let editedId = UUID()
        var entries = gibberishCorpus()
        // First pass caches the entry's (gibberish) lowercased text under its
        // content hash.
        entries.append(Entry(id: editedId, title: "vontrel", text: "quibbins darnop weffle nurmid",
                             createdAt: Date().addingTimeInterval(-86_400), updatedAt: Date()))
        let query = RetrievalQuery(currentMessage: "how did marathon training go")
        XCTAssertTrue(EntryRetriever.retrieve(query, entries: entries).isAmbient)

        // Same id, new content — a stale cache would still score the old text
        // and miss the now-obvious match.
        entries[entries.count - 1] = Entry(id: editedId, title: "marathon training",
                                           text: "long marathon run this morning",
                                           createdAt: Date().addingTimeInterval(-86_400), updatedAt: Date())
        let after = EntryRetriever.retrieve(query, entries: entries)
        XCTAssertFalse(after.isAmbient)
        XCTAssertTrue(after.entries.contains { $0.id == editedId })
    }

    func test_ambientContextBlock_usesBackgroundHeader() {
        let result = EntryRetriever.retrieve(
            RetrievalQuery(currentMessage: "nothing in common here at all"),
            entries: gibberishCorpus()
        )
        XCTAssertTrue(result.isAmbient)
        XCTAssertTrue(result.contextBlock.contains("background context"))
    }

    // MARK: - Word-boundary keyword matching (gold-set failure, 2026-08-23)

    /// `text.contains(term)` matched inside words. On the 262-entry persona
    /// corpus that was the single largest source of wrong citations: `go` hit
    /// *going* and *ago*, `back` hit *background*, `into` hit almost every
    /// entry. "When did I go skiing last winter?" — a question the corpus does
    /// not answer — scored 5.0 on that noise and produced three citations.
    func test_containsWord_doesNotMatchInsideAWord() {
        XCTAssertFalse(EntryRetriever.containsWord("i went for a walk an hour ago", "go"))
        XCTAssertFalse(EntryRetriever.containsWord("the background hum of the office", "back"))
        XCTAssertFalse(EntryRetriever.containsWord("a classroom full of people", "class"))
        XCTAssertTrue(EntryRetriever.containsWord("let it go, finally", "go"))
        XCTAssertTrue(EntryRetriever.containsWord("walked back home", "back"))
    }

    /// Ordinary inflection still has to match, or every plural becomes a miss.
    /// The allowance is a short tail on a term long enough for the prefix to
    /// mean something — which is exactly why `go` above does not qualify.
    func test_containsWord_allowsShortInflection() {
        XCTAssertTrue(EntryRetriever.containsWord("first pottery class tonight", "classes"))
        XCTAssertTrue(EntryRetriever.containsWord("pottery classes on thursdays", "class"))
        XCTAssertTrue(EntryRetriever.containsWord("moving apartments this weekend", "apartment"))
    }

    /// A term in most of the corpus must not outvote a term in two entries.
    /// Normalised so ~5% document frequency weighs exactly 1.0, which is what
    /// keeps `keywordSignalMin` meaning what it always meant.
    func test_termWeight_scalesWithRarity() {
        let corpus = 262
        let rare = EntryRetriever.termWeight(documentFrequency: 2, corpus: corpus)
        let typical = EntryRetriever.termWeight(documentFrequency: 13, corpus: corpus)
        let common = EntryRetriever.termWeight(documentFrequency: 82, corpus: corpus)
        XCTAssertEqual(typical, 1.0, accuracy: 0.05, "5% of the corpus is the 1.0 reference")
        XCTAssertGreaterThan(rare, typical)
        XCTAssertLessThan(common, typical)
        XCTAssertLessThanOrEqual(rare, 2.0, "a hapax must not clear the bar alone")
        XCTAssertGreaterThanOrEqual(common, 0.15)
    }

    /// Below `idfMinCorpus` the document frequencies are noise, so the weights
    /// stay flat and every small-corpus expectation above is unchanged.
    func test_termWeight_isFlatOnSmallCorpora() {
        XCTAssertEqual(EntryRetriever.termWeight(documentFrequency: 1, corpus: 6), 1.0)
        XCTAssertEqual(EntryRetriever.termWeight(documentFrequency: 5, corpus: 6), 1.0)
    }

    // MARK: - Date windows (gold-set failure, 2026-08-23)

    private func datedCorpus() -> [Entry] {
        let cal = Calendar.current
        func at(_ year: Int, _ month: Int, _ day: Int) -> Date {
            cal.date(from: DateComponents(year: year, month: month, day: day))!
        }
        return [
            Entry(title: "Nonna", text: "Mom called about Nonna, the scan came back worse than anyone expected.",
                  createdAt: at(2025, 12, 18)),
            Entry(title: "Nonna", text: "Nonna died this morning. The half second of silence before the words.",
                  createdAt: at(2026, 2, 9)),
            Entry(title: "Nonna", text: "Thinking about Nonna again, the yellow light in her kitchen.",
                  createdAt: at(2026, 4, 12)),
            Entry(title: "Quiet", text: "An ordinary Tuesday, nothing much to report, made eggs properly.",
                  createdAt: at(2025, 12, 4))
        ]
    }

    /// A month in the question is a hard constraint. Without it, "What did I
    /// hear about Nonna's health in December?" cited the February and April
    /// entries — the right subject, the wrong months, and no way for the
    /// reader to tell.
    func test_namedMonth_restrictsToThatMonth() {
        let result = EntryRetriever.retrieve(
            RetrievalQuery(currentMessage: "What did I hear about Nonna's health in December?"),
            entries: datedCorpus()
        )
        XCTAssertFalse(result.isEmpty)
        XCTAssertFalse(result.isAmbient)
        let cal = Calendar.current
        for entry in result.entries {
            XCTAssertEqual(cal.component(.month, from: entry.date), 12, "cited outside the named month")
            XCTAssertEqual(cal.component(.year, from: entry.date), 2025)
        }
    }

    /// When the named range holds nothing that touches the question, the honest
    /// answer is nothing — not recent life as ambient background. Returning
    /// ambient here is what put three citations on "When did I go skiing last
    /// winter?" and a March 2026 citation on "What did I write about my brother
    /// in 2025?".
    func test_namedRangeWithNothingInIt_returnsEmpty() {
        let result = EntryRetriever.retrieve(
            RetrievalQuery(currentMessage: "What did I write about skiing in 2019?"),
            entries: datedCorpus()
        )
        XCTAssertTrue(result.isEmpty, "a range with no entries at all must not fall back to ambient")
    }

    /// A subject the journal never mentions must not come back grounded.
    ///
    /// Semantic similarity alone will always crown something — NL embeddings
    /// score every entry warmly against any well-formed English sentence — so
    /// "What have I said about my dog?" came back with citations against a
    /// corpus containing no dog. Zero lexical support across every content term
    /// is what tells the two apart.
    func test_subjectAbsentFromTheJournal_staysUngrounded() {
        let result = EntryRetriever.retrieve(
            RetrievalQuery(currentMessage: "What have I said about my dog?"),
            entries: datedCorpus()
        )
        XCTAssertTrue(result.isEmpty || result.isAmbient,
                      "a subject the journal never mentions must not ground the reply")
    }

    /// Inside a named range the words have to land too: the right year and the
    /// wrong subject is still the wrong answer.
    func test_namedRangeWithoutTheSubject_returnsEmpty() {
        let result = EntryRetriever.retrieve(
            RetrievalQuery(currentMessage: "What did I write about my brother in 2025?"),
            entries: datedCorpus()
        )
        XCTAssertTrue(result.isEmpty, "no 2025 entry mentions a brother")
    }

    /// A question with no date must behave exactly as it did before.
    func test_noDateInQuestion_leavesRetrievalUnchanged() {
        let result = EntryRetriever.retrieve(
            RetrievalQuery(currentMessage: "What have I written about Nonna?"),
            entries: datedCorpus()
        )
        XCTAssertFalse(result.isEmpty)
        XCTAssertGreaterThan(result.entries.count, 1)
    }

    // MARK: - Origin questions (gold-set failure, 2026-08-23)

    /// "When did I first…" wants the earliest entry on the topic. Recency
    /// scoring argues for the opposite, and did: seven of fifteen wrong-citation
    /// failures on the gold set were this shape.
    func test_seeksOrigin_recognisesOriginQuestions() {
        for q in ["When did I first say I was burnt out?",
                  "When did I start pottery classes?",
                  "When did I get back into running?",
                  "When did the crunch on Atlas begin?",
                  "When did I take up swimming?"] {
            XCTAssertTrue(EntryRetriever.seeksOrigin(q), q)
        }
    }

    /// Must stay off questions where recency is the whole point — a recency cue
    /// wins even when the sentence also carries an origin word.
    func test_seeksOrigin_ignoresRecencyQuestions() {
        for q in ["What did I write last week?",
                  "How have I been sleeping lately?",
                  "What did I start last month?",
                  "When did I last go running?",
                  "What have I been up to recently?"] {
            XCTAssertFalse(EntryRetriever.seeksOrigin(q), q)
        }
    }

    /// The behaviour that matters: with several entries on one subject, an
    /// origin question surfaces the oldest first.
    func test_originQuestion_putsTheEarliestEntryFirst() {
        let day = 86_400.0
        let entries = [
            Entry(title: "Pottery", text: "First pottery class tonight and I was genuinely terrible at it.",
                  createdAt: Date(timeIntervalSinceNow: -200 * day)),
            Entry(title: "Pottery", text: "Pottery again, the wheel is finally starting to make sense.",
                  createdAt: Date(timeIntervalSinceNow: -60 * day)),
            Entry(title: "Pottery", text: "Pottery class, glazed the bowl I made last month.",
                  createdAt: Date(timeIntervalSinceNow: -10 * day))
        ]
        let result = EntryRetriever.retrieve(
            RetrievalQuery(currentMessage: "When did I start pottery classes?"),
            entries: entries
        )
        XCTAssertFalse(result.isEmpty, "pottery should match on keywords alone")
        XCTAssertEqual(result.entries.first?.date, entries[0].createdAt,
                       "an origin question must lead with the earliest match")
    }
}
