import XCTest
@testable import MeetMemento

/// Spec 017 R9. The budget is a contract, not a habit — so these tests pin the
/// properties the contract depends on, not the specific numbers the shares
/// happen to produce today.
final class ContextBudgetTests: XCTestCase {

    // MARK: The no-change guarantee

    /// The most important test here. On a build that cannot read the window,
    /// the budget must reproduce exactly what this module already shipped —
    /// otherwise introducing the budget silently changes what every reply is
    /// grounded in, and any behaviour change would be attributed to the wrong
    /// cause later.
    func test_unavailableWindow_reproducesTheShippedCaps() {
        let budget = ContextBudget(window: .unavailable)

        XCTAssertEqual(budget.maxRetrievedEntries, EntryRetriever.maxEntries)
        XCTAssertEqual(budget.maxEntryChars, EntryRetriever.maxContentChars)
        XCTAssertEqual(budget.maxHistoryTurns, 6)
        XCTAssertEqual(budget.maxHistoryCharsPerTurn, 320)
    }

    /// `.unavailable` must stay tied to `EntryRetriever`'s constants rather than
    /// copying them, so retuning retrieval cannot silently desynchronise the
    /// two.
    func test_legacyLimits_areTheRetrieversOwnConstants() {
        XCTAssertEqual(RetrievalLimits.legacyDefault.maxEntries, EntryRetriever.maxEntries)
        XCTAssertEqual(RetrievalLimits.legacyDefault.maxContentChars, EntryRetriever.maxContentChars)
    }

    // MARK: Scaling

    /// A bigger window buys more depth — below the latency clamp (spec 029
    /// Amendment A). Past the clamp, prefill time is what a bigger payload
    /// buys, so growth is deliberately flat; the growth assertion therefore
    /// uses windows on the growing side of the curve.
    func test_largerWindow_buysMoreDepth_belowTheClamp() {
        let small = ContextBudget(window: .reported(tokens: 2048))
        let large = ContextBudget(window: .reported(tokens: 4096))

        XCTAssertGreaterThan(large.maxRetrievedEntries, small.maxRetrievedEntries)
        XCTAssertGreaterThanOrEqual(large.maxHistoryTurns, small.maxHistoryTurns)
        XCTAssertGreaterThan(large.totalAllocatedChars, small.totalAllocatedChars)
    }

    /// Monotonic (non-decreasing) across the whole range the platform can
    /// report — 4096 on iOS 26 devices, 8192 on newer iOS 27 hardware, 32768 on
    /// PCC. None of those numbers appear in the module; they are inputs here
    /// because a test is exactly where a concrete window belongs. Growth up to
    /// the latency clamp, then flat — never a regression.
    func test_budget_isMonotonicUpToTheClamp() {
        let windows = [1024, 2048, 4096, 8192, 16384, 32768]
        let budgets = windows.map { ContextBudget(window: .reported(tokens: $0)) }

        for (smaller, larger) in zip(budgets, budgets.dropFirst()) {
            XCTAssertLessThanOrEqual(smaller.maxRetrievedEntries, larger.maxRetrievedEntries)
            XCTAssertLessThanOrEqual(smaller.maxHistoryTurns, larger.maxHistoryTurns)
            XCTAssertLessThanOrEqual(smaller.totalAllocatedChars, larger.totalAllocatedChars)
        }
    }

    // MARK: Latency clamp (spec 029 Amendment A)

    /// The clamp is a prefill-latency budget, not a window constant: however
    /// large the reported window, evidence stays within 3 500 chars and history
    /// within 2 000, because payload past that buys time-to-first-token, not
    /// answer quality.
    func test_reportedWindows_respectTheLatencyBudgets() {
        for tokens in [4096, 8192, 16384] {
            let budget = ContextBudget(window: .reported(tokens: tokens))

            XCTAssertLessThanOrEqual(
                budget.maxRetrievedEntries * budget.maxEntryChars, 3_500,
                "evidence payload for \(tokens) exceeds the prefill-latency budget"
            )
            XCTAssertLessThanOrEqual(
                budget.maxHistoryTurns * budget.maxHistoryCharsPerTurn, 2_000,
                "history payload for \(tokens) exceeds the prefill-latency budget"
            )
        }
    }

    /// Once the clamp binds, a bigger window changes nothing: the budget is
    /// flat by design, so window growth can never smuggle latency back in.
    func test_beyondTheClamp_budgetIsFlat() {
        let clamped = ContextBudget(window: .reported(tokens: 4096))
        for tokens in [8192, 16384, 32768] {
            let larger = ContextBudget(window: .reported(tokens: tokens))

            XCTAssertEqual(larger.maxRetrievedEntries, clamped.maxRetrievedEntries)
            XCTAssertEqual(larger.maxEntryChars, clamped.maxEntryChars)
            XCTAssertEqual(larger.maxHistoryTurns, clamped.maxHistoryTurns)
            XCTAssertEqual(larger.maxHistoryCharsPerTurn, clamped.maxHistoryCharsPerTurn)
        }
    }

    // MARK: Clamps

    /// A degenerate window must not produce a budget that retrieves nothing —
    /// an ungrounded reply is worse than a short one.
    func test_tinyOrZeroWindow_stillGroundsTheReply() {
        for tokens in [0, 1, 256] {
            let budget = ContextBudget(window: .reported(tokens: tokens))

            XCTAssertGreaterThanOrEqual(budget.maxRetrievedEntries, 3)
            XCTAssertGreaterThanOrEqual(budget.maxEntryChars, 240)
            XCTAssertGreaterThanOrEqual(budget.maxHistoryTurns, 2)
            XCTAssertGreaterThanOrEqual(budget.maxHistoryCharsPerTurn, 160)
        }
    }

    /// And a very large window must not bury the question under evidence —
    /// technology/01 §3 is explicit that crowding out the actual prompt
    /// produces worse answers, not better ones.
    func test_hugeWindow_isCeilinged() {
        let budget = ContextBudget(window: .reported(tokens: 1_000_000))

        XCTAssertLessThanOrEqual(budget.maxRetrievedEntries, 24)
        XCTAssertLessThanOrEqual(budget.maxEntryChars, 1_400)
        XCTAssertLessThanOrEqual(budget.maxHistoryTurns, 20)
        XCTAssertLessThanOrEqual(budget.maxHistoryCharsPerTurn, 800)
    }

    // MARK: Fits

    /// The allocation must leave room for instructions, the question, and the
    /// model's own output. Retrieval and history together claim 53% of the
    /// window by design, so the derived payload must stay well inside it.
    func test_allocationFitsInsideTheWindow() {
        for tokens in [4096, 8192, 32768] {
            let budget = ContextBudget(window: .reported(tokens: tokens))
            let approxTokensUsed = Double(budget.totalAllocatedChars) / 4.0

            XCTAssertLessThan(approxTokensUsed, Double(tokens) * 0.7,
                              "budget for \(tokens) leaves too little room for instructions and output")
        }
    }

    // MARK: Degraded routes

    /// A degraded route narrows retrieval: the smaller model handles less
    /// context better than more (technology/02 §8). Still floored, so a degraded
    /// reply is grounded in something.
    func test_narrowed_halvesEntriesWithAFloor() {
        let limits = RetrievalLimits(budget: ContextBudget(window: .reported(tokens: 8192)))
        let narrowed = limits.narrowed()

        XCTAssertLessThan(narrowed.maxEntries, limits.maxEntries)
        XCTAssertGreaterThanOrEqual(narrowed.maxEntries, 2)
        XCTAssertEqual(narrowed.maxContentChars, limits.maxContentChars,
                       "narrowing drops entries, not the depth of each one")

        XCTAssertGreaterThanOrEqual(RetrievalLimits(maxEntries: 1, maxContentChars: 500).narrowed().maxEntries, 2)
    }
}
