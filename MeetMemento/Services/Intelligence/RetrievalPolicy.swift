//
//  RetrievalPolicy.swift
//  MeetMemento
//
//  Maps a classified turn (TurnClassifier) to a retrieval decision and, once
//  retrieval has run, to the stance instruction handed to the model. The
//  stance line is the deterministic contract that stops the small on-device
//  model from grounding every reply in journal entries ("You wrote about…"):
//  logic decides the stance, the prompt obeys it.
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
    /// No retrieval at all — social, acknowledgement, meta, offdomain.
    case none
    /// Followup: re-derive the previous grounding from the last substantive
    /// user turn (see `RetrievalPolicy.followupAnchor`).
    case reusePrevious
    /// Share: retrieve on the current message only; grounded only above the
    /// high confidence bar.
    case currentOnly(highBar: Bool)
    /// Journal/reflective question: current message weighted with recent history.
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
            return "[Turn: casual — reply in one or two friendly sentences; do not mention journal entries; leave citedRefs empty]"
        case .aboutApp:
            return "[Turn: about the app — briefly say what you can do together; no journal references; leave citedRefs empty]"
        case .outsideScope:
            return "[Turn: outside scope — say that's outside what you can see, then gently return to them; no journal references; leave citedRefs empty]"
        case .sharing:
            return "[Turn: sharing — respond to what they said as a friend; mention an entry only if it clearly helps; do not force an insight or citation]"
        case .followupThread:
            return "[Turn: follow-up — continue your previous point in the same thread; do not restart, re-acknowledge, or begin a new entry inventory]"
        case .journalGrounded:
            return "[Turn: journal question — answer conversationally first; use at most one natural entry reference if it helps; ask one forward question; list only the refs you used in citedRefs; do not list multiple entries unless they asked what they wrote about a topic]"
        case .noMatch:
            return "[Turn: journal question, no matches — say you don't see entries about that yet and invite them to write about it; do not invent any]"
        }
    }

    /// Whether the citation fallback (attach top retrieved refs when the model
    /// cites none) is allowed. Casual/sharing turns must keep empty citations.
    var isGrounded: Bool {
        self == .journalGrounded || self == .followupThread
    }

    /// The tag name up to the inline instructions — e.g. "[Turn: casual". The
    /// ask prompt's stance contract must mention every one of these
    /// (PromptStanceSyncTests keeps prompt and policy from drifting apart).
    var tagPrefix: String {
        promptLine.components(separatedBy: " — ").first ?? promptLine
    }
}

enum RetrievalPolicy {

    /// The retrieval decision matrix.
    static func mode(for turn: TurnType) -> RetrievalMode {
        switch turn {
        case .social, .acknowledgement, .meta, .offdomain:
            return .none
        case .followup:
            return .reusePrevious
        case .share:
            return .currentOnly(highBar: true)
        case .journalQuery, .reflectiveQuestion:
            return .currentWeighted
        }
    }

    /// Walks history backwards to the last substantive user message — the one
    /// a followup like "tell me more" refers to. Skips user turns that are
    /// themselves followups/acknowledgements/social, checks at most
    /// `maxWalkback` user turns, and returns nil when none qualifies (caller
    /// falls back to `.currentWeighted` on the current message).
    static func followupAnchor(history: [ChatTurn], maxWalkback: Int = 4) -> String? {
        var checked = 0
        for turn in history.reversed() where turn.role == .user {
            checked += 1
            if checked > maxWalkback { return nil }
            let type = TurnClassifier.classify(turn.text, hasHistory: true)
            switch type {
            case .followup, .acknowledgement, .social, .meta:
                continue
            default:
                return turn.text
            }
        }
        return nil
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
