//
//  RetrievalPolicy.swift
//  withMemento
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
/// the first line of the user prompt. Plain prose, never bracketed tags: the
/// model echoes tag syntax back as output format (058, Study VI).
enum TurnStance: String, Sendable, Equatable, CaseIterable {
    case casual
    case aboutApp
    case outsideScope
    case sharing
    case followupThread
    case journalGrounded
    case nearbyOnly
    case noMatch

    var promptLine: String {
        switch self {
        case .casual:
            return "This is a casual turn. Meet them in a friendly way, then ask one question. "
                + "Bring up the notebook only if they did. No headings or lists. Leave citedRefs empty."
        case .aboutApp:
            return "They are asking about the app. Briefly say what you can do together "
                + "as a short \"- \" list, then ask one question about what they want to look at. "
                + "No journal references. Leave citedRefs empty."
        case .outsideScope:
            return "This is outside what you can see. Say so, then gently return to them with one question. "
                + "No headings or lists. Leave citedRefs empty."
        case .sharing:
            return "They are sharing something. Follow what they said as a friend would, then ask one question. "
                + "No ### unless they asked for the journal, and do not force an insight or citation."
        case .followupThread:
            return "This is a follow-up. Continue your previous point in the same thread, "
                + "stay with the notebook if the thread is about it, then ask one question. "
                + "Do not restart with a new heading or begin a new entry inventory."
        case .journalGrounded:
            return "This is a journal question. Meet them, place one moment from the journal moments "
                + "listed below, stay with that moment, then ask one question. "
                + "List entries only if they asked what they wrote about a topic. "
                + "Put only the refs you used in citedRefs, and do not reopen an entry already used in this thread."
        case .nearbyOnly:
            return "This is a journal question with nothing direct in the journal. "
                + "Do not quote a nearer entry and then deny it. Ask one question back toward them."
        case .noMatch:
            return "This is a journal question with no matching entry. "
                + "Do not invent an entry, quote a nearer one, or change the subject. No heading, no list. "
                + "Invite them to write only if they asked what they have written and the archive is empty."
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

    /// The turn line's opening sentence — e.g. "This is a casual turn." — which
    /// names the stance in plain words. Tests use it to find the line in a prompt.
    var label: String {
        guard let end = promptLine.firstIndex(of: ".") else { return promptLine }
        return String(promptLine[...end])
    }
}

enum RetrievalPolicy {

    /// The retrieval decision matrix. `history` is required for follow-up:
    /// reuse the previous grounding only when the anchor classifies as a
    /// journal ask — "tell me more" after a share must not retrieve.
    static func mode(for turn: TurnType, history: [ChatTurn] = []) -> RetrievalMode {
        switch turn {
        case .social, .acknowledgement, .meta, .offdomain, .share, .reflectiveQuestion, .quantitative, .correction:
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
            case .followup, .acknowledgement, .social, .meta, .correction:
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
    static func stance(
        turn: TurnType, retrieval: RetrievalResult, question: String = ""
    ) -> TurnStance {
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
            // Three outcomes, not two. `.noMatch` used to cover both "retrieval
            // returned nothing" and "retrieval returned recent life as ambient
            // background" — but the prompt ships the ambient text either way, so
            // the second case told the model to deny what it was holding, and the
            // model resolved that by doing both (spec 044, evidence row 4).
            //
            // `.empty` is the only state where the prompt genuinely carries no
            // evidence: the empty archive, a named window nothing touches, and
            // the diversify guard. That is what `.noMatch` now means.
            if retrieval.isEmpty { return .noMatch }
            if retrieval.isAmbient {
                // A list of what they wrote may name the hits. A miss does not
                // quote the nearest entry and then deny it.
                return EvidenceLadder.isInventory(question) ? .journalGrounded : .noMatch
            }
            return .journalGrounded
        case .quantitative:
            // Counts are Swift facts; light/casual narration is optional.
            return .casual
        case .reflectiveQuestion:
            // Reflective musings stay warm conversation; grounded reports are
            // reserved for explicit journal asks.
            return .sharing
        case .correction:
            return .followupThread
        }
    }
}
