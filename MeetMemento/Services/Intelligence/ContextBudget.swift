//
//  ContextBudget.swift
//  MeetMemento
//
//  Spec 017 R9 / CONSTITUTION §4 rule 5's corollary: "no hardcoded model context
//  budgets — the window is 4096/8192/32768 depending on device and zone; read
//  contextSize at runtime and size retrieved-entry payloads against it."
//
//  Pure Swift: the window arrives as a value, so every derivation here is
//  testable without a model, a device, or the SDK.
//
//  **Why `ContextWindow` has an `.unavailable` case.** `SystemLanguageModel`
//  gained `contextSize` in the iOS 27 SDK, back-deployed to iOS 26.4 at runtime.
//  The iOS 26 SDK's FoundationModels.swiftinterface does not declare the member
//  at all — verified, zero occurrences — so on the toolchain CI builds with, the
//  property does not exist to call. `#available` cannot help: this is an SDK
//  problem, not a runtime one.
//
//  The tempting workaround is to substitute 4096 when the read is unavailable.
//  That is precisely what this module is forbidden to do, and writing it as
//  `4 << 10` to slip past a grep would be worse: the code would carry a window
//  literal while claiming not to. So absence is modelled as a state instead. On
//  a build that cannot read the window, the budget falls back to the caps this
//  module already ships — values tuned empirically against real replies, not
//  derived from any assumed window — and nothing here pretends to know a number
//  it cannot obtain.
//

import Foundation

/// The model's usable context window, or an honest statement that this build
/// cannot read it.
enum ContextWindow: Equatable, Sendable {
    /// The runtime reported a window, in tokens.
    case reported(tokens: Int)
    /// This SDK exposes no way to read the window. Not an error, and explicitly
    /// not "assume 4096" — see the file header.
    case unavailable
}

/// Per-request payload caps derived from the runtime window.
///
/// Allocation shares are documented rather than magic: the prompt also has to
/// hold instructions, the user's question, the personalization section, and the
/// model's own output, so retrieved evidence and history get a bounded slice
/// each. Reasoning tokens count against the window too (technology/02 §5), which
/// is why the shares are conservative rather than filling the space.
struct ContextBudget: Equatable, Sendable {
    /// How many retrieved journal entries may enter the prompt.
    let maxRetrievedEntries: Int
    /// How much of each retrieved entry is kept.
    let maxEntryChars: Int
    /// How many prior conversation turns are replayed.
    let maxHistoryTurns: Int
    /// How much of each replayed turn is kept.
    let maxHistoryCharsPerTurn: Int
    /// The window this budget was derived from, for logging and tests.
    let window: ContextWindow

    // MARK: Allocation shares

    /// Share of the window given to retrieved journal evidence.
    private static let retrievalShare = 0.35
    /// Share of the window given to replayed conversation history.
    private static let historyShare = 0.18
    /// Rough characters per token for English prose. A heuristic, and treated as
    /// one: every derived value is clamped, so a bad estimate degrades the
    /// budget rather than overflowing the window.
    private static let charsPerToken = 4.0

    // MARK: Clamps
    //
    // These bound the *derivation*, they are not window sizes. The lower bounds
    // keep a tiny window usable; the upper bounds stop a very large window from
    // burying the question under evidence, which technology/01 §3 warns produces
    // worse answers, not better ones.

    private static let minRetrievedEntries = 3
    private static let maxRetrievedEntriesCeiling = 24
    private static let minEntryChars = 240
    private static let maxEntryCharsCeiling = 1_400
    private static let minHistoryTurns = 2
    private static let maxHistoryTurnsCeiling = 20
    private static let minHistoryCharsPerTurn = 160
    private static let maxHistoryCharsPerTurnCeiling = 800

    // MARK: Baseline (window unreadable)
    //
    // The caps this module shipped before it could read a window. Empirically
    // tuned against real replies — deliberately NOT back-derived from any
    // assumed window, which is what makes them honest to use when the window is
    // unknown. `EntryRetriever` owns the retrieval pair; they are referenced,
    // never duplicated.

    private static var baselineEntryChars: Int { EntryRetriever.maxContentChars }
    private static var baselineRetrievedEntries: Int { EntryRetriever.maxEntries }
    private static let baselineHistoryTurns = 6
    private static let baselineHistoryCharsPerTurn = 320

    init(window: ContextWindow) {
        self.window = window

        switch window {
        case .unavailable:
            maxRetrievedEntries = Self.baselineRetrievedEntries
            maxEntryChars = Self.baselineEntryChars
            maxHistoryTurns = Self.baselineHistoryTurns
            maxHistoryCharsPerTurn = Self.baselineHistoryCharsPerTurn

        case .reported(let tokens):
            let usableTokens = Double(max(tokens, 0))
            let retrievalChars = usableTokens * Self.retrievalShare * Self.charsPerToken
            let historyChars = usableTokens * Self.historyShare * Self.charsPerToken

            // Entry count grows with the window; per-entry depth grows with what
            // is left after the count. Splitting it this way means a bigger
            // window buys both more evidence and more of each piece, rather than
            // one at the other's expense.
            let entries = Int((retrievalChars / Double(Self.baselineEntryChars)).rounded(.down))
            maxRetrievedEntries = min(max(entries, Self.minRetrievedEntries), Self.maxRetrievedEntriesCeiling)
            let perEntry = Int((retrievalChars / Double(maxRetrievedEntries)).rounded(.down))
            maxEntryChars = min(max(perEntry, Self.minEntryChars), Self.maxEntryCharsCeiling)

            let turns = Int((historyChars / Double(Self.baselineHistoryCharsPerTurn)).rounded(.down))
            maxHistoryTurns = min(max(turns, Self.minHistoryTurns), Self.maxHistoryTurnsCeiling)
            let perTurn = Int((historyChars / Double(maxHistoryTurns)).rounded(.down))
            maxHistoryCharsPerTurn = min(max(perTurn, Self.minHistoryCharsPerTurn), Self.maxHistoryCharsPerTurnCeiling)
        }
    }

    /// Total characters this budget may put into a prompt, excluding
    /// instructions and the question itself. Used by tests to prove the
    /// allocation stays inside the window it was derived from.
    var totalAllocatedChars: Int {
        maxRetrievedEntries * maxEntryChars + maxHistoryTurns * maxHistoryCharsPerTurn
    }
}
