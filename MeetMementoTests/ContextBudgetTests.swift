//
//  ContextBudgetTests.swift
//  MeetMementoTests
//
//  Spec 017 R9: budgets derive from the RUNTIME context window — they scale
//  monotonically with the window, respect their clamps, and reproduce
//  sensible behavior at the known window sizes. (Window-size literals are
//  allowed here — tests are the documented exception in the
//  no-hardcoded-budget gate.)
//

import XCTest
@testable import MeetMemento

final class ContextBudgetTests: XCTestCase {

    func test_smallWindow_matchesLegacyScaleBehavior() {
        // The iOS 26 on-device window. Should land near the tuned legacy caps
        // (7 entries × 600 chars, 8-turn history) — not radically tighter or
        // looser.
        let budget = ContextBudget(contextTokens: 4096)
        XCTAssertTrue((6...10).contains(budget.maxRetrievedEntries), "\(budget.maxRetrievedEntries)")
        XCTAssertTrue((500...900).contains(budget.maxEntryChars), "\(budget.maxEntryChars)")
        XCTAssertTrue((6...10).contains(budget.maxHistoryTurns), "\(budget.maxHistoryTurns)")
        XCTAssertTrue((300...600).contains(budget.maxHistoryCharsPerTurn))
    }

    func test_largeWindow_scalesUpDepth() {
        // The iOS 27 on-device window on newer devices: the budget must
        // actually use the extra room (the whole point of runtime budgeting).
        let small = ContextBudget(contextTokens: 4096)
        let large = ContextBudget(contextTokens: 8192)
        XCTAssertGreaterThan(large.maxRetrievedEntries, small.maxRetrievedEntries)
        XCTAssertGreaterThanOrEqual(large.maxEntryChars, small.maxEntryChars)
        XCTAssertGreaterThanOrEqual(large.maxHistoryTurns, small.maxHistoryTurns)
    }

    func test_monotonic_neverDecreasesWithWindow() {
        var previous = ContextBudget(contextTokens: 1024)
        for tokens in stride(from: 2048, through: 32768, by: 1024) {
            let budget = ContextBudget(contextTokens: tokens)
            XCTAssertGreaterThanOrEqual(budget.maxRetrievedEntries, previous.maxRetrievedEntries)
            XCTAssertGreaterThanOrEqual(budget.maxEntryChars, previous.maxEntryChars)
            XCTAssertGreaterThanOrEqual(budget.maxHistoryTurns, previous.maxHistoryTurns)
            XCTAssertGreaterThanOrEqual(budget.maxHistoryCharsPerTurn, previous.maxHistoryCharsPerTurn)
            previous = budget
        }
    }

    func test_clampsHold_atExtremes() {
        let tiny = ContextBudget(contextTokens: 0)
        XCTAssertGreaterThanOrEqual(tiny.maxRetrievedEntries, 4, "floor guards degenerate windows")
        XCTAssertGreaterThanOrEqual(tiny.maxEntryChars, 500)
        XCTAssertGreaterThanOrEqual(tiny.maxHistoryTurns, 4)

        let huge = ContextBudget(contextTokens: 1_000_000)
        XCTAssertLessThanOrEqual(huge.maxRetrievedEntries, 14, "cap guards runaway prompts")
        XCTAssertLessThanOrEqual(huge.maxEntryChars, 1200)
        XCTAssertLessThanOrEqual(huge.maxHistoryTurns, 12)
        XCTAssertLessThanOrEqual(huge.maxHistoryCharsPerTurn, 600)
    }

    func test_totalPromptEstimate_staysInsideWindow() {
        // The derived caps, fully spent, must fit the window they came from
        // with headroom for instructions + output (the allocation contract).
        for tokens in [2048, 4096, 8192, 32768] {
            let budget = ContextBudget(contextTokens: tokens)
            let retrievalChars = budget.maxRetrievedEntries * budget.maxEntryChars
            let historyChars = budget.maxHistoryTurns * budget.maxHistoryCharsPerTurn
            let estimatedTokens = (retrievalChars + historyChars) / ContextBudget.estimatedCharsPerToken
            XCTAssertLessThan(
                Double(estimatedTokens), Double(tokens) * 0.65,
                "window \(tokens): evidence+history must leave ≥35% for instructions/output"
            )
        }
    }
}
