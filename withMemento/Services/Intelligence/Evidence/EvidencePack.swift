//
//  EvidencePack.swift
//  withMemento
//
//  Spec 050 R1: the moments one Ask turn may quote or date, built by Swift
//  from the retrieval the prompt already carries. The model can only point
//  at a slot with {{quote:n}} / {{date:n}}; ReplyRenderer inserts the words,
//  so a quote on screen is always text Swift already had. No Foundation
//  Models import.
//

import Foundation

/// One moment the renderer may insert. Every field comes from a
/// `RetrievedEntry`; the model authors none of it.
struct EvidenceSlot: Sendable, Equatable, Identifiable {
    /// The n in `{{quote:n}}` / `{{date:n}}` — the entry's `[ref n]` in the
    /// context block, so the model uses one number for both.
    let index: Int
    let entryId: UUID
    let date: Date
    /// `EntryRetriever.formattedDate`, the form a notebook moment's heading uses.
    let displayDate: String
    /// A contiguous span of `passageText`, or nil when no span is clean
    /// enough to insert (the slot can still be dated).
    let quoteText: String?
    /// The span stops before its sentence does; the renderer adds an ellipsis.
    let quoteIsClipped: Bool
    /// The excerpt the model saw. A span the model copies instead of writing
    /// a marker is checked against this.
    let passageText: String

    var id: Int { index }
}

/// A Swift-computed magnitude `{{stat:id}}` may insert. Grammar only in v1:
/// the statistic channel stays skip-AFM and `[Computed]` narration is
/// unchanged, so live packs carry none.
struct StatSlot: Sendable, Equatable, Identifiable {
    let id: String
    let kind: String
    let label: String
    /// `FactMagnitude.word` — never a digit.
    let spokenMagnitude: String
}

struct EvidencePack: Sendable, Equatable {
    /// Never higher than the turn-level state the channel was gated on.
    let state: EvidenceState
    /// Empty unless `.matched`: ambient rows are background, not citations.
    let slots: [EvidenceSlot]
    /// The date of every entry whose text the prompt carries, matched or
    /// ambient. A date the model writes survives only if it is one of these.
    let contextDates: [Date]
    let stats: [StatSlot]
    let retrievalWasEmpty: Bool
    let retrievalWasAmbient: Bool

    static let empty = EvidencePack.unquotable(.none, dates: [], wasEmpty: true, wasAmbient: false)

    /// A pack with no slots: `.none`, or `.ambient` with the shipped dates.
    static func unquotable(
        _ state: EvidenceState,
        dates: [Date],
        wasEmpty: Bool,
        wasAmbient: Bool
    ) -> EvidencePack {
        EvidencePack(
            state: state,
            slots: [],
            contextDates: dates,
            stats: [],
            retrievalWasEmpty: wasEmpty,
            retrievalWasAmbient: wasAmbient
        )
    }

    /// Whether the prompt carries a journal block this turn.
    var carriesEvidence: Bool { state != .none }

    func slot(_ index: Int) -> EvidenceSlot? {
        slots.first { $0.index == index }
    }

    func stat(_ id: String) -> StatSlot? {
        stats.first { $0.id == id }
    }
}

// MARK: - Model-facing legend (spec 050 R2)

extension EvidencePack {

    static let legendHeader = "[Evidence]\nMarkers only: the app swaps each for that entry's exact words or date. "
        + "Never type a journal quote or date yourself, never change a number, never use italics."
    static let legendFooter = "If none fits, use no markers."
    static let ambientNote = "[Evidence: background only — no quote or date markers this turn. "
        + "Speak about these entries in your own words; never quote them, never use italics.]"
    static let noneNote = "[Evidence: none — no quote or date markers this turn. "
        + "Never write a journal quote, a journal date, or italics.]"

    /// What the journal recipe is told about markers this turn. The matched
    /// legend lists each slot's exact words beside its markers, so the model
    /// chooses a slot rather than recalling a sentence. Nil on channels that
    /// never retrieve: their prompts never mention markers.
    func promptLegend(channel: ReplyChannel) -> String? {
        guard channel.allowsRetrieval else { return nil }
        switch state {
        case .matched:
            guard !slots.isEmpty else { return nil }
            let rows = slots.map { slot -> String in
                let date = "\(slot.index). {{date:\(slot.index)}} = \(slot.displayDate)"
                guard let quote = slot.quoteText else { return date + " · no quote" }
                let shown = slot.quoteIsClipped ? quote + "…" : quote
                return date + " · {{quote:\(slot.index)}} = \"\(shown)\""
            }
            return ([Self.legendHeader] + rows + [Self.legendFooter]).joined(separator: "\n")
        case .ambient:
            return Self.ambientNote
        case .none:
            return Self.noneNote
        }
    }

    /// The context block without its `quoted:` lines. The legend carries the
    /// quotable span now, and an ambient row must not advertise one. The
    /// `[ref n | date]` lines stay exactly as built: `citedRefs` addresses them.
    static func promptContextBlock(_ block: String) -> String {
        block.components(separatedBy: "\n")
            .filter { !$0.hasPrefix("quoted: \"") }
            .joined(separator: "\n")
    }
}

enum EvidencePackBuilder {

    /// Mirrors what `buildAskPrompt` ships. A miss (`.noMatch`, `.nearbyOnly`,
    /// an empty archive) or a channel that does not retrieve carries no
    /// evidence block, so it gets no pack — whatever rows are attached.
    static func build(
        retrieval: RetrievalResult,
        stance: TurnStance,
        channel: ReplyChannel,
        archiveEmpty: Bool = false
    ) -> EvidencePack {
        let miss = stance == .noMatch || stance == .nearbyOnly || archiveEmpty
        guard channel.allowsRetrieval, !miss,
              !retrieval.isEmpty, !retrieval.contextBlock.isEmpty else {
            return .unquotable(.none, dates: [], wasEmpty: retrieval.isEmpty, wasAmbient: retrieval.isAmbient)
        }
        let dates = retrieval.entries.map(\.date)
        if retrieval.isAmbient {
            return .unquotable(.ambient, dates: dates, wasEmpty: false, wasAmbient: true)
        }
        return EvidencePack(
            state: .matched,
            slots: retrieval.entries.map(slot(for:)),
            contextDates: dates,
            stats: [],
            retrievalWasEmpty: false,
            retrievalWasAmbient: false
        )
    }

    static func slot(for entry: RetrievedEntry) -> EvidenceSlot {
        let quote = quote(for: entry)
        return EvidenceSlot(
            index: entry.ref,
            entryId: entry.id,
            date: entry.date,
            displayDate: EntryRetriever.formattedDate(entry.date),
            quoteText: quote?.text,
            quoteIsClipped: quote?.isClipped ?? false,
            passageText: entry.text
        )
    }

    /// The first candidate that is a clean, contiguous span of the excerpt:
    /// the retrieved `quotedSpan`, then every sentence the extractor accepts,
    /// then its whole-or-prefix fallback. A candidate that is not verbatim
    /// is rejected whoever produced it.
    static func quote(for entry: RetrievedEntry) -> (text: String, isClipped: Bool)? {
        var candidates: [String] = []
        if let span = entry.quotedSpan { candidates.append(span) }
        candidates += QuotedSpanExtractor.candidates(from: entry.text)
        if let fallback = QuotedSpanExtractor.extract(from: entry.text) {
            candidates.append(fallback)
        }
        var seen = Set<String>()
        for raw in candidates {
            let candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard seen.insert(candidate).inserted else { continue }
            if let accepted = accept(candidate, in: entry.text) { return accepted }
            if entry.quotedSpan == raw {
                AppLogger.log("[Evidence] ref=\(entry.ref) quotedSpan rejected", type: .info)
            }
        }
        return nil
    }

    /// Characters that would break the `*…*` wrapper, the marker grammar,
    /// or the renderer's placeholders if a quote carried them.
    static let unquotableCharacters: CharacterSet = {
        var set = CharacterSet(charactersIn: "*_`{}")
        set.formUnion(.newlines)
        if let low = Unicode.Scalar(0xE000), let high = Unicode.Scalar(0xF8FF) {
            set.insert(charactersIn: low...high)
        }
        return set
    }()

    private static let sentenceEnd: Set<Character> = [".", "!", "?", "…"]
    private static let closingMarks: Set<Character> = ["\"", "”", "’", "'", ")"]

    /// Accepts `candidate` if it appears verbatim in `passage`. A span that
    /// stops mid-sentence is cut back to a word boundary and flagged.
    static func accept(_ candidate: String, in passage: String) -> (text: String, isClipped: Bool)? {
        guard !candidate.isEmpty, candidate.count <= QuotedSpanExtractor.maxChars,
              candidate.rangeOfCharacter(from: unquotableCharacters) == nil,
              let range = passage.range(of: candidate) else { return nil }

        let core = candidate.reversed().drop { closingMarks.contains($0) }
        if let last = core.first, sentenceEnd.contains(last) {
            return (candidate, false)
        }
        // Mid-sentence. Drop a trailing word that may be cut short: the
        // passage continues inside it, or the passage itself ends there.
        var text = candidate
        let cutInsideWord = range.upperBound == passage.endIndex
            || passage[range.upperBound].isLetter || passage[range.upperBound].isNumber
        if cutInsideWord {
            guard let space = text.lastIndex(where: \.isWhitespace) else { return nil }
            text = String(text[..<space])
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:—–-").union(.whitespaces))
        guard text.split(whereSeparator: \.isWhitespace).count >= 3 else { return nil }
        return (text, true)
    }
}
