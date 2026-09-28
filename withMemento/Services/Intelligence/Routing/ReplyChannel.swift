//
//  ReplyChannel.swift
//  withMemento
//
//  Spec 039: the only mapping from TurnType (+ photos) to a generation
//  recipe. Rank 0 is cheapest. Skipping a rank (ask@14 + 512 tokens on a
//  greeting) is a spec violation. No `import FoundationModels` — pure Swift.
//

import Foundation

/// Generation recipe for one Ask turn. Resolved after SafetyRouter and
/// TurnClassifier; consumed by `prepareAsk` and PromptRegistry.
enum ReplyChannel: String, Sendable, Equatable, CaseIterable {
    case phatic
    case continuer
    case meta
    case companion
    case thread
    case notebook
    case statistic
    case redirect

    /// Exhaustive map. Photo bump: any in-session image never resolves to
    /// phatic or continuer — bump to companion unless the text is a journal
    /// ask (notebook) or meta (meta).
    ///
    /// Evidence gates the recipe. A journal question against an empty archive
    /// is never notebook or thread (spec 046 R3). Default `.matched` keeps
    /// callers that have not loaded the archive on today's map.
    static func resolve(
        turn: TurnType,
        hasImages: Bool,
        evidence: EvidenceState = .matched
    ) -> ReplyChannel {
        let base: ReplyChannel
        switch turn {
        case .social: base = .phatic
        case .acknowledgement: base = .continuer
        case .meta: base = .meta
        case .share, .reflectiveQuestion: base = .companion
        case .followup: base = .thread
        case .journalQuery: base = .notebook
        case .quantitative: base = .statistic
        case .offdomain: base = .redirect
        case .correction: base = .thread
        }
        let bumped: ReplyChannel
        if hasImages, base == .phatic || base == .continuer {
            bumped = .companion
        } else {
            bumped = base
        }
        return bumped.gated(by: evidence)
    }

    /// Empty archive may only leave notebook and thread. It never upgrades
    /// a lighter channel into them.
    func gated(by evidence: EvidenceState) -> ReplyChannel {
        guard evidence == .none else { return self }
        switch self {
        case .notebook, .thread: return .companion
        default: return self
        }
    }

    /// The recipes `prewarmConversation` warms for the next turn: one per
    /// distinct instruction text a live send can resolve to on device.
    /// `continuer` shares `chat-light@4` with phatic and `meta` shares the
    /// lensed companion prompt, so both adopt without their own slot;
    /// `redirect` is the lens-free companion text; `thread` is the
    /// follow-up recipe — every second turn of a journal conversation
    /// missed the pool while only notebook was warmed. `statistic` never
    /// reaches the model. `ReplyChannelTests` pins the coverage.
    static let speculativeChannels: [ReplyChannel] = [
        .phatic, .companion, .redirect, .thread, .notebook
    ]

    /// Ranks 0–1 leave ask@15 for `chat-light@4`.
    var usesLightPrompt: Bool {
        switch self {
        case .phatic, .continuer, .statistic: return true
        default: return false
        }
    }

    /// Statistic answers are Swift facts. Skip `SystemLanguageModel` so a
    /// count still lands when Apple Intelligence is off or not ready.
    var requiresOnDeviceModel: Bool { self != .statistic }

    /// Rank 2 / redirect leave ask@15 for `chat-companion@1`. Notebook and
    /// RAG-thread keep the heavy recipe.
    var usesCompanionPrompt: Bool {
        switch self {
        case .companion, .meta, .redirect: return true
        default: return false
        }
    }

    /// User prompt is `[Move:]` + latest message, not the ask@15 `[Turn:]` /
    /// `[Shape:]` stack. Light and companion recipes both need this; mixing
    /// chat-companion@1 instructions with Meet/Sit/Open is what killed replies.
    var usesShortAssembler: Bool { usesLightPrompt || usesCompanionPrompt }

    /// Body-only Generable (`LightAskAnswer`) — no `citedRefs`. Companion and
    /// meta never emit citations, so they share the light schema.
    ///
    /// Typed notebook/thread keep `AskAnswer`: the journal recipe asks for
    /// citations and the chat page renders them.
    ///
    /// **Spoken** notebook/thread drop to the light schema. `citedRefs` is the
    /// last field in `AskAnswer`'s decode order, so every step it costs lands
    /// *after* the final audible word — pure dead air at the end of a
    /// half-duplex turn, spent on an array TTS never speaks. Narration is the
    /// one path where that tail is all cost and no benefit.
    ///
    /// Citations do not disappear from the persisted turn: `reconcileCitations`
    /// treats an empty ref list by matching verbatim quoted spans in the body
    /// first, then falling back to the top retrieved entries. Spoken journal
    /// turns therefore cite from retrieval rather than from the model's own
    /// declaration — less precisely attributed, not absent.
    func usesBodyOnlySchema(spoken: Bool = false, evidence: EvidenceState = .matched) -> Bool {
        if evidence == .none { return true }
        switch self {
        case .phatic, .continuer, .redirect, .companion, .meta, .statistic: return true
        case .thread, .notebook: return spoken
        }
    }

    /// Spoken follow-ups with no journal anchor use companion, not thread.
    /// Classification stays `.followup`; only the recipe changes so the
    /// listen → answer loop hits `chat-companion@1` instead of ask@15.
    /// Journal-anchored follow-ups (`reusePrevious`) stay on thread + RAG.
    func applyingSpokenFollowUpRecipe(
        turn: TurnType, history: [ChatTurn], spoken: Bool
    ) -> ReplyChannel {
        guard spoken, self == .thread else { return self }
        guard RetrievalPolicy.mode(for: turn, history: history) == .none else {
            return self
        }
        return .companion
    }

    /// L1 "About this person" is omitted on phatic, continuer, and redirect.
    var omitsLens: Bool {
        switch self {
        case .phatic, .continuer, .redirect, .statistic: return true
        default: return false
        }
    }

    /// Default RAG path is notebook only. Thread may retrieve when the
    /// follow-up is journal-anchored (`reusePrevious`).
    var allowsRetrieval: Bool {
        switch self {
        case .notebook, .thread: return true
        default: return false
        }
    }

    /// Spec 039 R1 token caps. Light caps are one spoken sentence plus a
    /// question; the two channels that run the full `ask@14` recipe get room
    /// for it.
    ///
    /// `.thread` used to drop to 128 when RAG had not run. Measured in the
    /// chat eval gate on 2026-08-23: every one of ten follow-up turns on that
    /// path truncated mid-sentence — 510 and 446 mean characters against a
    /// ~460-character budget — and **0 of 10 reached the closing question**
    /// that `ask@14` requires. The cap was the whole of `rule.noOpen`, the
    /// gate's single largest failure family.
    ///
    /// The asymmetry never made sense on its own terms either: a follow-up
    /// runs the same Meet → Notebook → Sit → Open recipe whether or not
    /// retrieval hit, so budgeting it at a quarter of the length asked for one
    /// outcome only — a reply cut off before it finished a sentence.
    /// `retrievalRan` still selects the temperature, where the distinction is
    /// real.
    ///
    /// Narration (`spoken: true`) never raises a cap. Companion drops to 80
    /// (one or two spoken sentences plus a question); meta stays 128 for
    /// about-the-app lists. Notebook/thread drop to 256 so Meet + one Sit
    /// beat + Open still fit without a spoken essay.
    /// `deep` is the suggestion-card analysis path: the person tapped a card
    /// asking the archive to be read across many entries, and is waiting on a
    /// synthesis rather than a chat reply. Only notebook/thread honour it, and
    /// only when typed — narration keeps its 256 so a spoken answer never
    /// becomes an essay. Typed questions the person wrote themselves stay at
    /// 512, so ordinary chat latency is unchanged.
    func maximumResponseTokens(retrievalRan: Bool, spoken: Bool = false, deep: Bool = false) -> Int {
        switch self {
        case .phatic: return 80
        case .continuer, .statistic: return 64
        case .meta: return 128
        case .companion: return spoken ? 80 : 128
        case .thread, .notebook:
            if spoken { return 256 }
            if deep { return 1024 }
            return PromptExperiments.typedNotebookCap256 ? 256 : 512
        case .redirect: return 80
        }
    }

    /// Light / companion / redirect stay warmer. Notebook and RAG thread
    /// stay grounded at 0.7.
    var temperature: Double {
        switch self {
        case .phatic, .continuer, .meta, .companion, .redirect, .statistic: return 0.9
        case .thread, .notebook: return 0.7
        }
    }

    /// Thread without RAG uses the companion temperature.
    func temperature(retrievalRan: Bool) -> Double {
        if self == .thread { return retrievalRan ? 0.7 : 0.9 }
        return temperature
    }
}
