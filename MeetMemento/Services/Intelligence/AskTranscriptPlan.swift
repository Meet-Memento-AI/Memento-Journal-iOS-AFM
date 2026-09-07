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
    /// Session 10 + chat-speed: hashed so a tool-bearing session is never
    /// adopted as a no-tool one. Live Ask and `prewarmConversation` both
    /// leave this **false** so iOS 27 notebook/thread turns can adopt the
    /// idle pool. `SearchJournalTool` attaches only after a speculative miss.
    let attachesSearchTool: Bool
    /// SHA-256 over the rendered entries — the adoption key for speculative
    /// sessions. Collision-resistant so a stale speculation can never serve
    /// the wrong conversation.
    let fingerprint: String

    /// Marks the optional few-shot pair so it can never be mistaken for a
    /// stored turn. Persistence tests pin that this string never reaches
    /// `LocalChatStore` / `assistantContentJSON`.
    static let exemplarMarker = "[Exemplar]"

    static let exemplarUser = """
    [Turn: journal question]
    \(exemplarMarker) What did I write about the hike?
    """

    static let exemplarAssistant = """
    You were up Mount Tamalpais with Maya when the fog broke.

    ### 21 days ago
    *Four hours up, and at the top it broke open completely.*

    The climb and the quiet at the top sat in the same day.

    What do you still remember from that view?
    """

    /// The one shared truncation: `history.suffix(maxHistoryTurns)`, each turn
    /// capped to `maxHistoryCharsPerTurn` — exactly the depth the old inline
    /// history block carried. `includeExemplar` is honored only when the
    /// Session 7 kill-switch is on and history is empty (notebook first turn).
    static func build(
        instructions: String,
        history: [ChatTurn],
        budget: ContextBudget,
        includeExemplar: Bool = false,
        attachesSearchTool: Bool = false
    ) -> AskTranscriptPlan {
        var entries: [Entry] = [.instructions(instructions)]
        if includeExemplar, PromptExperiments.exemplarTurnEnabled, history.isEmpty {
            entries.append(.userPrompt(exemplarUser))
            entries.append(.assistantResponse(exemplarAssistant))
        }
        for turn in history.suffix(budget.maxHistoryTurns) {
            let text = String(turn.text.prefix(budget.maxHistoryCharsPerTurn))
            entries.append(turn.role == .user ? .userPrompt(text) : .assistantResponse(text))
        }
        return AskTranscriptPlan(
            entries: entries,
            attachesSearchTool: attachesSearchTool,
            fingerprint: Self.fingerprint(of: entries, attachesSearchTool: attachesSearchTool)
        )
    }

    /// Stable across processes (unlike `Hasher`) and unambiguous: each entry
    /// contributes a role tag and its text with distinct separators, so
    /// ("ab","c") can never collide with ("a","bc") or a role swap.
    static func fingerprint(of entries: [Entry], attachesSearchTool: Bool = false) -> String {
        var digest = SHA256()
        digest.update(data: Data([attachesSearchTool ? 0x74 : 0x00]))
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
