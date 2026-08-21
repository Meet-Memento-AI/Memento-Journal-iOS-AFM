import XCTest
@testable import MeetMemento

/// Spec 037 R6 / R7: unit contracts for the six recall goldens (counts removed)
/// and the 3–5 entry Ask cap. Full Apple Evaluations harness stays 022;
/// PersonaGate (026) still applies separately.
final class ConversationalRecallContractTests: XCTestCase {

    private func askText(degraded: Bool = false) -> String {
        PromptRegistry.instructions(for: .ask, degraded: degraded).text
    }

    // MARK: R6 — six goldens (prompt contracts, no AFM)

    func test_emotionLabel_isForbidden() {
        for degraded in [false, true] {
            let text = askText(degraded: degraded)
            XCTAssertTrue(
                text.contains("name their emotions") || text.contains("Never name their emotions"),
                "degraded=\(degraded): prompt must forbid naming feelings"
            )
            XCTAssertFalse(text.contains("you seemed anxious"))
        }
    }

    func test_interpretation_isForbidden() {
        let text = askText()
        XCTAssertTrue(text.contains("do not name the meaning") || text.contains("Put evidence in front of them"))
        XCTAssertTrue(text.contains("interpret character the evidence does not state")
                      || text.contains("Never name their emotions"))
    }

    func test_advice_isForbidden_andSafetyGateRemains() {
        for degraded in [false, true] {
            let text = askText(degraded: degraded)
            XCTAssertTrue(text.contains("give advice") || text.contains("Never give advice"),
                          "degraded=\(degraded)")
            XCTAssertTrue(text.contains("you should"), "degraded=\(degraded)")
            XCTAssertTrue(text.contains("Safety hard bans"), "degraded=\(degraded)")
            XCTAssertTrue(text.contains("crisis counseling"), "degraded=\(degraded)")
        }
    }

    func test_fabrication_andCitedRefs_unchanged() {
        for degraded in [false, true] {
            let text = askText(degraded: degraded)
            XCTAssertTrue(text.contains("Never invent entries"), "degraded=\(degraded)")
        }
        XCTAssertTrue(askText().contains("citedRefs"))
        XCTAssertFalse(askText().contains("eleven entries"), "goldens must not teach counts")
        XCTAssertTrue(askText().contains("across several entries this spring"))
        XCTAssertTrue(askText().contains("never \"nine entries\""))
    }

    func test_emptyRecall_isDirect() {
        for degraded in [false, true] {
            let text = askText(degraded: degraded)
            XCTAssertTrue(
                text.contains("don't see anything from that stretch"),
                "degraded=\(degraded)"
            )
            XCTAssertFalse(
                text.contains("invite them to write about it"),
                "degraded=\(degraded): unsolicited write-invite is gone"
            )
        }
        XCTAssertTrue(TurnStance.noMatch.promptLine.contains("do not change the subject"))
        XCTAssertTrue(TurnStance.noMatch.promptLine.contains("do not invent"))
        XCTAssertFalse(TurnStance.noMatch.promptLine.contains("answer and stop"))
    }

    func test_journalTurn_mustNotSkipSit() {
        for degraded in [false, true] {
            let text = askText(degraded: degraded)
            XCTAssertTrue(text.contains("must not skip Sit"), "degraded=\(degraded)")
            XCTAssertTrue(text.contains("Meet them"), "degraded=\(degraded)")
            XCTAssertTrue(text.contains("Notebook"), "degraded=\(degraded)")
            XCTAssertTrue(text.contains("Open"), "degraded=\(degraded)")
            XCTAssertFalse(text.contains("Follow it exactly"), "degraded=\(degraded)")
            XCTAssertFalse(text.contains("answer and stop"), "degraded=\(degraded)")
            XCTAssertFalse(text.contains("three to five"), "degraded=\(degraded)")
            XCTAssertFalse(text.contains("Three to ten"), "degraded=\(degraded)")
        }
    }

    // MARK: R5 / R1 — version and notebook voice

    func test_ask9_versions() {
        XCTAssertEqual(PromptRegistry.instructions(for: .ask).version, "ask@10")
        XCTAssertEqual(PromptRegistry.instructions(for: .ask, degraded: true).version, "ask-degraded@10")
    }

    func test_notebookVoice_andShapeContract() {
        let text = askText()
        XCTAssertTrue(text.contains("notebook beside them"))
        XCTAssertTrue(text.contains("[Shape:]"))
        XCTAssertTrue(text.contains("reproduce any quoted field exactly"))
        XCTAssertTrue(text.contains("Do not reopen an entry already used in"))
        XCTAssertTrue(text.contains("must not skip Sit"))
        XCTAssertTrue(text.contains("heading1 and heading2 stay empty"))
        XCTAssertTrue(text.contains("praise them for journaling")
                      || text.contains("Never praise journaling"))
        XCTAssertTrue(text.contains("count, or frequency")
                      || text.contains("number, count, or frequency"))
    }

    // MARK: R7 — 3–5 entry cap

    // MARK: - Evidence starvation

    private func entries(_ n: Int) -> [RetrievedEntry] {
        (0..<n).map {
            RetrievedEntry(ref: $0 + 1, id: UUID(), date: Date(),
                           text: "entry \($0)", quotedSpan: nil)
        }
    }

    /// The regression that made later turns collapse to one sentence.
    ///
    /// `sliceForPrompt` preferred unsurfaced entries but only fell back to the
    /// ranked slice when NONE were fresh. By turn four or five the strong hits
    /// were all denylisted, so the prompt carried a single marginal entry —
    /// and a prompt with one thin entry plus "everything you claim must come
    /// from the evidence block" earns exactly one thin sentence.
    func test_sliceForPrompt_fillsToCapEvenWhenMostEntriesAreSurfaced() {
        var pool = SessionCandidatePool()
        let all = entries(5)
        pool.ingest(all)
        // Everything but the last has already been shown this thread.
        pool.markSurfaced(all.dropLast().map(\.id))

        let sliced = pool.sliceForPrompt(all, cap: 5)

        XCTAssertEqual(sliced.count, 5, "the prompt must never be under-filled")
        XCTAssertEqual(sliced.first?.id, all.last?.id, "the fresh entry still leads")
    }

    func test_sliceForPrompt_prefersFreshEntriesFirst() {
        var pool = SessionCandidatePool()
        let all = entries(4)
        pool.ingest(all)
        pool.markSurfaced([all[0].id, all[1].id])

        let sliced = pool.sliceForPrompt(all, cap: 4)

        XCTAssertEqual(sliced.map(\.id), [all[2].id, all[3].id, all[0].id, all[1].id])
        XCTAssertEqual(sliced.map(\.ref), [1, 2, 3, 4], "refs renumber 1...n")
    }

    func test_sliceForPrompt_capAndEmptyCases() {
        var pool = SessionCandidatePool()
        let all = entries(3)
        pool.ingest(all)

        XCTAssertEqual(pool.sliceForPrompt(all, cap: 5).count, 3, "fewer entries than cap")
        XCTAssertEqual(pool.sliceForPrompt(all, cap: 2).count, 2, "cap honoured")

        pool.markSurfaced(all.map(\.id))
        XCTAssertEqual(pool.sliceForPrompt(all, cap: 3).count, 3,
                       "all surfaced still grounds the reply")
    }

    // MARK: - Conversation identity

    private typealias Anchor = FoundationModelsIntelligenceService.ConversationAnchor

    /// Pool and cadence used to reset only on an empty history, so opening a
    /// *different existing* conversation kept the previous thread's
    /// surfaced-ID denylist and starved the new one.
    func test_conversationAnchor_distinguishesSwitchFromContinuation() {
        let first = ChatTurn(role: .user, text: "how was spring")
        let reply = ChatTurn(role: .assistant, text: "...")

        let opening = try! XCTUnwrap(Anchor(history: [first]))
        let continued = try! XCTUnwrap(Anchor(history: [first, reply]))
        XCTAssertTrue(opening.continues(into: continued), "same thread, one turn later")

        let other = try! XCTUnwrap(Anchor(history: [ChatTurn(role: .user, text: "different chat")]))
        XCTAssertFalse(opening.continues(into: other), "a different opener is a different thread")
    }

    func test_conversationAnchor_isNilForAnEmptyHistory() {
        XCTAssertNil(Anchor(history: []))
    }

    func test_retrieverMaxEntries_isFive() {
        XCTAssertEqual(EntryRetriever.maxEntries, 5)
        XCTAssertGreaterThanOrEqual(EntryRetriever.maxEntries, 3)
    }

    func test_askRetrievalLimits_neverExceedFive() {
        for tokens in [2048, 4096, 8192, 16384, 32768] {
            let limits = RetrievalLimits(budget: ContextBudget(window: .reported(tokens: tokens)))
            XCTAssertLessThanOrEqual(
                limits.maxEntries, EntryRetriever.maxEntries,
                "window \(tokens) leaked \(limits.maxEntries) entries into Ask"
            )
            XCTAssertGreaterThanOrEqual(limits.maxEntries, 2)
        }
        let unavailable = RetrievalLimits(budget: ContextBudget(window: .unavailable))
        XCTAssertEqual(unavailable.maxEntries, 5)
    }
}
