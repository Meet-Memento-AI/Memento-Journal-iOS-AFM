//
//  ContextBudget.swift
//  MeetMemento
//
//  Per-request context budgeting (spec 017 R9 / CONSTITUTION §4 rule 5
//  corollary): "context budgeting is a contract, not a habit." The model's
//  window is a RUNTIME value that differs by device, OS, and zone — the
//  boundary reads `contextSize` per request and derives every retrieval and
//  history cap from it here. No token-window literals appear in this file or
//  anywhere in the module (CI: check_no_hardcoded_context_budgets.sh); on
//  hardware with a larger window (AFM 3-class devices) the budget scales up
//  automatically instead of leaving context unused.
//
//  Allocation model (documented shares of the total window, char-estimated):
//    ~35%  retrieved journal evidence (the depth lever)
//    ~18%  conversation history
//    rest  instructions + stance/question + structured output headroom
//  The chars-per-token estimate is deliberately conservative (English prose
//  runs ~4 chars/token); crowd-out is instrumented at the boundary via the
//  generation latency/log line, and token-precise budgeting upgrades to
//  `tokenCount(for:)` with the iOS 27 SDK pass.
//
//  No `import FoundationModels` — pure Swift.
//

import Foundation

struct ContextBudget: Sendable, Equatable {
    /// The runtime window (from the model, per request — never hardcoded).
    let contextTokens: Int

    /// Retrieval caps (consumed via `RetrievalLimits`).
    let maxRetrievedEntries: Int
    let maxEntryChars: Int

    /// Conversation-history caps for prompt assembly.
    let maxHistoryTurns: Int
    let maxHistoryCharsPerTurn: Int

    // MARK: Derivation constants (shares and clamps, not window sizes)

    /// Conservative prose estimate; ~4 chars/token for English.
    static let estimatedCharsPerToken = 4
    /// Share of the window given to retrieved journal evidence.
    static let retrievalShare = 0.35
    /// Share of the window given to conversation history.
    static let historyShare = 0.18
    /// Target chars for a "moderate" entry excerpt (drives the entry count).
    static let targetEntryChars = 700
    /// Target chars for one history turn (drives the turn count).
    static let targetHistoryTurnChars = 350

    init(contextTokens: Int) {
        self.contextTokens = max(contextTokens, 0)
        let charBudget = self.contextTokens * Self.estimatedCharsPerToken

        let retrievalChars = Int(Double(charBudget) * Self.retrievalShare)
        let entries = (retrievalChars / Self.targetEntryChars).clamped(to: 4...14)
        self.maxRetrievedEntries = entries
        self.maxEntryChars = (retrievalChars / entries).clamped(to: 500...1200)

        let historyChars = Int(Double(charBudget) * Self.historyShare)
        let turns = (historyChars / Self.targetHistoryTurnChars).clamped(to: 4...12)
        self.maxHistoryTurns = turns
        self.maxHistoryCharsPerTurn = (historyChars / turns).clamped(to: 300...600)
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }
}
