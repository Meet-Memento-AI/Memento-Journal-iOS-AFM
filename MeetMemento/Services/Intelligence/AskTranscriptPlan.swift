//
//  AskTranscriptPlan.swift
//  MeetMemento
//
//  The pure, FoundationModels-free description of one ask turn's session
//  transcript (spec 029 Amendment A): resolved instructions plus the
//  budget-truncated history tail as alternating user/assistant turns. The
//  intelligence service maps this 1:1 onto a `Transcript` and a fresh
//  `LanguageModelSession(transcript:)` — history stops being re-sent as
//  inline prompt prose and its prefill can be paid ahead of time.
//
//  Speculation and serving both build their plan through `build(...)`, so the
//  truncation they hash can never disagree: a speculatively prewarmed session
//  is adopted iff the fingerprints match exactly. Stateless architecture
//  (spec 017 R9) is unchanged — every session is fresh, used once, and
//  derived from the store-owned history.
//
//  Deliberately does NOT import FoundationModels: the single-importer CI gate
//  (scripts/ci/check_single_intelligence_importer.sh) covers tests too, and
//  this type is what the fixture tests pin.
//

import CryptoKit
import Foundation

struct AskTranscriptPlan: Equatable, Sendable {
    enum Entry: Equatable, Sendable {
        case instructions(String)
        case userPrompt(String)
        case assistantResponse(String)
    }

    /// Instructions first, then the capped history tail in order.
    let entries: [Entry]
    /// SHA-256 over the rendered entries — the adoption key for speculative
    /// sessions. Collision-resistant so a stale speculation can never serve
    /// the wrong conversation.
    let fingerprint: String

    /// The one shared truncation: `history.suffix(maxHistoryTurns)`, each turn
    /// capped to `maxHistoryCharsPerTurn` — exactly the depth the old inline
    /// history block carried.
    static func build(
        instructions: String,
        history: [ChatTurn],
        budget: ContextBudget
    ) -> AskTranscriptPlan {
        var entries: [Entry] = [.instructions(instructions)]
        for turn in history.suffix(budget.maxHistoryTurns) {
            let text = String(turn.text.prefix(budget.maxHistoryCharsPerTurn))
            entries.append(turn.role == .user ? .userPrompt(text) : .assistantResponse(text))
        }
        return AskTranscriptPlan(entries: entries, fingerprint: Self.fingerprint(of: entries))
    }

    /// Stable across processes (unlike `Hasher`) and unambiguous: each entry
    /// contributes a role tag and its text with distinct separators, so
    /// ("ab","c") can never collide with ("a","bc") or a role swap.
    static func fingerprint(of entries: [Entry]) -> String {
        var digest = SHA256()
        for entry in entries {
            let tag: UInt8
            let text: String
            switch entry {
            case .instructions(let t): tag = 0x69; text = t   // 'i'
            case .userPrompt(let t): tag = 0x75; text = t     // 'u'
            case .assistantResponse(let t): tag = 0x61; text = t  // 'a'
            }
            digest.update(data: Data([tag, 0x1F]))
            digest.update(data: Data(text.utf8))
            digest.update(data: Data([0x1E]))
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Speculative next-turn sessions, keyed by `AskTranscriptPlan.fingerprint`.
/// Dual-slot: light and heavy recipes for the same history coexist; adopt
/// is exact-match and one-shot.
struct FingerprintPool<Value> {
    private var slots: [String: Value] = [:]

    mutating func store(_ value: Value, fingerprint: String) {
        slots[fingerprint] = value
    }

    mutating func take(matching fingerprint: String) -> Value? {
        slots.removeValue(forKey: fingerprint)
    }

    func has(matching fingerprint: String) -> Bool {
        slots[fingerprint] != nil
    }

    /// Replace the pool with a new pair (light + heavy). Drops stale history.
    mutating func replaceAll(_ pairs: [(fingerprint: String, value: Value)]) {
        slots = Dictionary(uniqueKeysWithValues: pairs.map { ($0.fingerprint, $0.value) })
    }

    var fingerprints: Set<String> { Set(slots.keys) }
    var count: Int { slots.count }
}
