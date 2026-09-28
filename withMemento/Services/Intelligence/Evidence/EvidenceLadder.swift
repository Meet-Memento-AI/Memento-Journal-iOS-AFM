//
//  EvidenceLadder.swift
//  withMemento
//
//  One rung, written by Swift, read by the model. The model does not pick it.
//  A miss does not quote the nearest entry. No Foundation Models import.
//

import Foundation

enum EvidenceRung: String, Sendable, Equatable {
    case exact
    case strong
    case ambiguous
    case none
    case conversationOnly
}

enum EvidenceLadder {

    static func isInventory(_ question: String) -> Bool {
        let q = question.lowercased()
        let cues = [
            "what have i written", "what did i write", "what have i been writing",
            "everything i wrote", "everything i've written", "show me what i",
            "what have i been"
        ]
        return cues.contains { q.contains($0) }
    }

    static func rung(
        stance: TurnStance,
        retrieval: RetrievalResult,
        question: String = ""
    ) -> EvidenceRung {
        switch stance {
        case .journalGrounded:
            let count = retrieval.entries.count
            if count >= 2 { return .strong }
            if count == 1 { return .exact }
            return .ambiguous
        case .noMatch, .nearbyOnly:
            return .none
        case .followupThread:
            guard !retrieval.isEmpty, !retrieval.isAmbient else { return .conversationOnly }
            return retrieval.entries.count >= 2 ? .strong : .exact
        case .casual, .aboutApp, .outsideScope, .sharing:
            return .conversationOnly
        }
    }

    /// The single line inserted into the prompt. Copy is fixed.
    ///
    /// `exact` points at the pack's markers instead of carrying the entry's
    /// words and a date the model would then retype (spec 050, amending 049
    /// R3's "You wrote X on [date]."). Without a quotable slot it names no text.
    static func promptLine(
        _ rung: EvidenceRung,
        retrieval: RetrievalResult,
        pack: EvidencePack? = nil
    ) -> String {
        switch rung {
        case .exact:
            guard !retrieval.isEmpty else { return "One entry may be what you mean." }
            guard let slot = pack?.slots.first else { return "One entry is about this." }
            let quote = slot.quoteText == nil ? "" : " {{quote:\(slot.index)}}"
            return "One entry answers this: {{date:\(slot.index)}}\(quote)."
        case .strong:
            return "Two entries are about this."
        case .ambiguous:
            return "One entry may be what you mean."
        case .none:
            return "I can't find an entry that supports that."
        case .conversationOnly:
            return "Stay with what they just said."
        }
    }
}
