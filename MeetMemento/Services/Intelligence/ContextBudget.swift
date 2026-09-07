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
///
/// **Latency clamp (spec 029 Amendment A).** Window-derived growth is further
/// clamped by prefill-latency budgets: prefill time scales with prompt tokens,
/// so past a point a bigger window buys time-to-first-token, not answer
/// quality. Confidence-conditional expansion ("spend more only when retrieval
/// is confident") was considered and rejected — the budget is computed before
/// retrieval runs, so no confidence signal exists yet to condition on.
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

    // MARK: Latency clamps
    //
    // These are PREFILL LATENCY budgets, not window constants (CONSTITUTION §4
    // rule 5 forbids the latter; nothing here encodes a window size). They cap
    // the total characters the derivation may hand to the prompt regardless of
    // how large the reported window is.

    /// Prefill-latency budget, not a window: prefill time scales with prompt
    /// tokens, and evidence beyond this buys TTFT, not answer quality
    /// (user decision, spec 029 Amendment A: clamp for speed).
    /// Spec 037 then caps how many of those entries enter the Ask prompt
    /// (`EntryRetriever.maxEntries` = 5); this character budget is unchanged.
    private static let maxEvidenceLatencyChars = 3_500   // historically 7 × 500
    private static let maxHistoryLatencyChars  = 2_000   // ≈ baseline 6 × 320

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

    /// Measured token counts for the three prompt slices (044 R7). Used when
    /// `tokenCount(for:)` is available. `charsPerToken` stays the fallback
    /// for `.unavailable` — this initializer never invents a window.
    struct TokenCounts: Equatable, Sendable {
        let instructions: Int
        let history: Int
        let evidence: Int
    }

    init(window: ContextWindow) {
        switch window {
        case .unavailable:
            self.init(
                maxRetrievedEntries: Self.baselineRetrievedEntries,
                maxEntryChars: Self.baselineEntryChars,
                maxHistoryTurns: Self.baselineHistoryTurns,
                maxHistoryCharsPerTurn: Self.baselineHistoryCharsPerTurn,
                window: window
            )
        case .reported(let tokens):
            let derived = Self.derived(usableTokens: Double(max(tokens, 0)))
            self.init(
                maxRetrievedEntries: derived.entries,
                maxEntryChars: derived.entryChars,
                maxHistoryTurns: derived.turns,
                maxHistoryCharsPerTurn: derived.turnChars,
                window: window
            )
        }
    }

    /// Token-aware budget (044 R7). Subtracts measured instruction tokens
    /// from a reported window, then applies the same share math. When the
    /// window is unreadable, identical to `init(window: .unavailable)`.
    init(tokenCounts: TokenCounts, window: ContextWindow) {
        switch window {
        case .unavailable:
            self.init(window: .unavailable)
        case .reported(let tokens):
            let remaining = max(0, tokens - tokenCounts.instructions)
            let derived = Self.derived(usableTokens: Double(remaining))
            self.init(
                maxRetrievedEntries: derived.entries,
                maxEntryChars: derived.entryChars,
                maxHistoryTurns: derived.turns,
                maxHistoryCharsPerTurn: derived.turnChars,
                window: window
            )
        }
    }

    private init(
        maxRetrievedEntries: Int,
        maxEntryChars: Int,
        maxHistoryTurns: Int,
        maxHistoryCharsPerTurn: Int,
        window: ContextWindow
    ) {
        self.maxRetrievedEntries = maxRetrievedEntries
        self.maxEntryChars = maxEntryChars
        self.maxHistoryTurns = maxHistoryTurns
        self.maxHistoryCharsPerTurn = maxHistoryCharsPerTurn
        self.window = window
    }

    private static func derived(usableTokens: Double) -> (
        entries: Int, entryChars: Int, turns: Int, turnChars: Int
    ) {
        let retrievalChars = usableTokens * retrievalShare * charsPerToken
        let historyChars = usableTokens * historyShare * charsPerToken

        // Entry count grows with the window; per-entry depth grows with what
        // is left after the count. Splitting it this way means a bigger
        // window buys both more evidence and more of each piece — up to the
        // latency clamp, past which growth is flat by design.
        //
        // The clamp is applied count-first (fewer, baseline-depth entries
        // beat many shallow ones), then per-entry chars are recomputed so
        // the product stays inside the latency budget. The grounding floors
        // always win over the clamp: a slow grounded reply beats a fast
        // ungrounded one.
        let entries = Int((retrievalChars / Double(baselineEntryChars)).rounded(.down))
        let latencyEntryCap = maxEvidenceLatencyChars / baselineEntryChars
        let maxRetrievedEntries = max(
            min(entries, maxRetrievedEntriesCeiling, latencyEntryCap),
            minRetrievedEntries
        )
        let perEntry = Int((retrievalChars / Double(maxRetrievedEntries)).rounded(.down))
        let latencyPerEntryCap = maxEvidenceLatencyChars / maxRetrievedEntries
        let maxEntryChars = max(
            min(perEntry, maxEntryCharsCeiling, latencyPerEntryCap),
            minEntryChars
        )

        let turns = Int((historyChars / Double(baselineHistoryCharsPerTurn)).rounded(.down))
        let latencyTurnCap = maxHistoryLatencyChars / baselineHistoryCharsPerTurn
        let maxHistoryTurns = max(
            min(turns, maxHistoryTurnsCeiling, latencyTurnCap),
            minHistoryTurns
        )
        let perTurn = Int((historyChars / Double(maxHistoryTurns)).rounded(.down))
        let latencyPerTurnCap = maxHistoryLatencyChars / maxHistoryTurns
        let maxHistoryCharsPerTurn = max(
            min(perTurn, maxHistoryCharsPerTurnCeiling, latencyPerTurnCap),
            minHistoryCharsPerTurn
        )
        return (maxRetrievedEntries, maxEntryChars, maxHistoryTurns, maxHistoryCharsPerTurn)
    }

    /// Total characters this budget may put into a prompt, excluding
    /// instructions and the question itself. Used by tests to prove the
    /// allocation stays inside the window it was derived from.
    var totalAllocatedChars: Int {
        maxRetrievedEntries * maxEntryChars + maxHistoryTurns * maxHistoryCharsPerTurn
    }
}
