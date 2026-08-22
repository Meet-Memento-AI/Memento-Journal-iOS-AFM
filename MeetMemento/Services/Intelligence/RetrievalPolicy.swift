//
//  RetrievalPolicy.swift
//  MeetMemento
//
//  Maps a classified turn (TurnClassifier) to a retrieval decision and, once
//  retrieval has run, to the stance instruction handed to the model. The
//  stance line is the deterministic contract that stops the small on-device
//  model from grounding every reply in journal entries ("You wrote about…"):
//  logic decides the stance; the prompt prefers that intent as guidance.
//
//  Followup turns are handled statelessly: retrieval is deterministic given
//  (query, entries) and entry vectors are cached in EmbeddingService, so
//  re-querying with the last substantive user turn reproduces the previous
//  grounding with zero session state (works across relaunches, no
//  cross-session bleed).
//
//  No `import FoundationModels` — pure Swift.
//

import Foundation

/// What retrieval, if any, to run for a turn.
enum RetrievalMode: Sendable, Equatable {
    /// No retrieval at all — social, acknowledgement, share, reflective,
    /// meta, offdomain, and follow-ups that are not anchored to a journal ask.
    case none
    /// Follow-up after a journal ask: re-derive the previous grounding from
    /// the last substantive user turn (see `RetrievalPolicy.followupAnchor`).
    case reusePrevious
    /// Current message only, optional high confidence bar. Unused on the
    /// ask@12 path (share no longer retrieves); kept so the switch stays
    /// exhaustive if a caller still requests it.
    case currentOnly(highBar: Bool)
    /// Journal question: current message weighted with recent history.
    case currentWeighted
}

/// The stance instruction for this turn — its `promptLine` is prepended as
/// the first line of the user prompt. Keep these strings in sync with the
/// stance contract in `PromptRegistry.ask` (enforced by PromptStanceSyncTests).
enum TurnStance: String, Sendable, Equatable, CaseIterable {
    case casual
    case aboutApp
    case outsideScope
    case sharing
    case followupThread
    case journalGrounded
    case noMatch

    var promptLine: String {
        switch self {
        case .casual:
            return "[Turn: casual — Meet them in a friendly way; Open only if a [Shape:] line asks; notebook only if they brought it up; no headings or lists; leave citedRefs empty]"
        case .aboutApp:
            return "[Turn: about the app — briefly say what you can do together; a short \"- \" list of capabilities; Open only if a [Shape:] line asks, about what they want to look at; no journal references; leave citedRefs empty]"
        case .outsideScope:
            return "[Turn: outside scope — say that's outside what you can see, then gently return to them; no headings or lists; leave citedRefs empty]"
        case .sharing:
            return "[Turn: sharing — follow what they said as a friend; no ### unless they asked for the journal; Open only if a [Shape:] line asks; do not force an insight or citation]"
        case .followupThread:
            return "[Turn: follow-up — continue your previous point in the same thread; Sit if the thread is about the notebook; Open only if a [Shape:] line asks; do not restart with a new heading or begin a new entry inventory]"
        case .journalGrounded:
            return "[Turn: journal question — Meet them, then one ### notebook moment, italic exact quote, then Sit; "
                + "lists only if they asked what they wrote about a topic; "
                + "reproduce any quoted field exactly; "
                + "Open only if a [Shape:] line asks; "
                + "list only the refs you used in citedRefs; "
                + "do not reopen an entry already used in this thread]"
        case .noMatch:
            return "[Turn: journal question, no matches — "
                + "Meet them, then say you don't see anything from that stretch; "
                + "no heading, no list; do not invent any; do not change the subject; "
                + "invite them once to write only if they asked what they have written "
                + "and the archive is empty]"
        }
    }

    /// Whether this stance type cites the journal even without looking at
    /// retrieval. Follow-up must use `isGrounded(retrieval:)` — it is grounded
    /// only when retrieval actually hit.
    var isGrounded: Bool {
        self == .journalGrounded
    }

    /// Citation fallback and evidence-block empty-copy. Casual/sharing stay
    /// ungrounded. Follow-up is grounded only on a real (non-empty, non-ambient)
    /// retrieval hit — "tell me more" after a share must not sneak a page on.
    func isGrounded(retrieval: RetrievalResult) -> Bool {
        switch self {
        case .journalGrounded:
            return true
        case .followupThread:
            return !retrieval.isEmpty && !retrieval.isAmbient
        default:
            return false
        }
    }

    /// The tag name up to the inline instructions — e.g. "[Turn: casual". The
    /// ask prompt's stance contract must mention every one of these
    /// (PromptStanceSyncTests keeps prompt and policy from drifting apart).
    var tagPrefix: String {
        promptLine.components(separatedBy: " — ").first ?? promptLine
    }
}

enum RetrievalPolicy {

    /// The retrieval decision matrix. `history` is required for follow-up:
    /// reuse the previous grounding only when the anchor classifies as a
    /// journal ask — "tell me more" after a share must not retrieve.
    static func mode(for turn: TurnType, history: [ChatTurn] = []) -> RetrievalMode {
        switch turn {
        case .social, .acknowledgement, .meta, .offdomain, .share, .reflectiveQuestion:
            return .none
        case .followup:
            return followupMode(history: history)
        case .journalQuery:
            return .currentWeighted
        }
    }

    /// `reusePrevious` only when the last substantive user turn was a journal
    /// ask. Otherwise `.none` so a social continuer does not load the notebook.
    static func followupMode(history: [ChatTurn]) -> RetrievalMode {
        guard let anchor = followupAnchor(history: history) else { return .none }
        return classifyHistoryTurn(anchor) == .journalQuery ? .reusePrevious : .none
    }

    /// Walks history backwards to the last substantive user message — the one
    /// a followup like "tell me more" refers to. Skips user turns that are
    /// themselves followups/acknowledgements/social, checks at most
    /// `maxWalkback` user turns, and returns nil when none qualifies (caller
    /// then uses `.none` — do not retrieve on a social continuer).
    static func followupAnchor(history: [ChatTurn], maxWalkback: Int = 4) -> String? {
        var checked = 0
        for turn in history.reversed() where turn.role == .user {
            checked += 1
            if checked > maxWalkback { return nil }
            let type = classifyHistoryTurn(turn.text)
            switch type {
            case .followup, .acknowledgement, .social, .meta:
                continue
            default:
                return turn.text
            }
        }
        return nil
    }

    // MARK: - History classification memo

    /// `followupAnchor` re-classifies up to `maxWalkback` prior user turns on
    /// every follow-up send, and the same history repeats send after send.
    /// Small bounded memo (FIFO eviction at `memoLimit`) keyed by turn text —
    /// classify(_:hasHistory: true) is deterministic, so the cached answer is
    /// exactly what a fresh call would return. NSLock-guarded; internal (not
    /// private) so tests can hit it directly.
    private static let memoLock = NSLock()
    private static var memo: [String: TurnType] = [:]
    private static var memoOrder: [String] = []
    private static let memoLimit = 32

    static func classifyHistoryTurn(_ text: String) -> TurnType {
        memoLock.lock()
        defer { memoLock.unlock() }
        if let cached = memo[text] { return cached }
        let type = TurnClassifier.classify(text, hasHistory: true)
        memo[text] = type
        memoOrder.append(text)
        if memoOrder.count > memoLimit {
            memo.removeValue(forKey: memoOrder.removeFirst())
        }
        return type
    }

    /// Resolves the final stance from the turn type and what retrieval
    /// actually produced. Explicit journal asks stay grounded/noMatch;
    /// shares and reflective musings stay conversational so chat does not
    /// become an entry report.
    static func stance(turn: TurnType, retrieval: RetrievalResult) -> TurnStance {
        switch turn {
        case .social, .acknowledgement:
            return .casual
        case .meta:
            return .aboutApp
        case .offdomain:
            return .outsideScope
        case .followup:
            return .followupThread
        case .share:
            // Emotional/event shares stay conversational — never promote to
            // journalGrounded just because retrieval found a weak topical hit.
            return .sharing
        case .journalQuery:
            // An explicit journal ask with no real match gets the honest answer.
            return (!retrieval.isEmpty && !retrieval.isAmbient) ? .journalGrounded : .noMatch
        case .reflectiveQuestion:
            // Reflective musings stay warm conversation; grounded reports are
            // reserved for explicit journal asks.
            return .sharing
        }
    }
}
