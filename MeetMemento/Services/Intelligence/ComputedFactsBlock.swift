//
//  ComputedFactsBlock.swift
//  MeetMemento
//
//  Session 12 / 045 R5 D: non-suppressed InsightFacts as a `[Computed]`
//  prompt block. Counts are words, never digits.
//

import Foundation

enum ComputedFactsBlock {
    /// Chat-speed: more than a handful of facts grows the prompt without
    /// helping the first token (044: high TTFT is a prompt problem).
    /// budget-exempt: 4
    static let maxFacts = 4

    /// Session 12 + chat-speed: `[Computed]` only on notebook turns that
    /// already retrieved (045). Facts come from the retrieved slice — not
    /// a second SwiftData scan of the whole corpus on the send path.
    static func entriesForFacts(
        channel: ReplyChannel,
        corpus: [Entry],
        retrieval: RetrievalResult
    ) -> [Entry] {
        guard channel == .notebook, !retrieval.isEmpty, !retrieval.isAmbient else {
            return []
        }
        let ids = Set(retrieval.entries.map(\.id))
        return corpus.filter { ids.contains($0.id) }
    }

    static func render(_ facts: [InsightFact]) -> String? {
        let usable = Array(facts.filter { !$0.isLowConfidence }.prefix(maxFacts))
        guard !usable.isEmpty else { return nil }
        var lines = [
            "[Computed]",
            "Narrate these Swift-computed facts. Do not invent counts or frequencies."
        ]
        for fact in usable {
            lines.append("- \(fact.kind.rawValue): \(fact.label) — \(FactMagnitude.word(for: fact.n))")
        }
        return lines.joined(separator: "\n")
    }
}
