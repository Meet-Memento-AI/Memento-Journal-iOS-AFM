//
//  ComputedFactsBlock.swift
//  MeetMemento
//
//  Session 12 / 045 R5 D: non-suppressed InsightFacts as a `[Computed]`
//  prompt block. Counts are words, never digits.
//

import Foundation

enum ComputedFactsBlock {
    static func render(_ facts: [InsightFact]) -> String? {
        let usable = facts.filter { !$0.isLowConfidence }
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
