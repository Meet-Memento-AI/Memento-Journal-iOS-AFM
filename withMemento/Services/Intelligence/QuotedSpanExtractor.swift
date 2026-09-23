//
//  QuotedSpanExtractor.swift
//  withMemento
//
//  Spec 037 follow-on / 019 archival quotes: pick one short contiguous
//  sentence from an entry for the evidence row's quoted field. Pure Swift —
//  no FoundationModels. Spec 050: `EvidencePackBuilder` walks `candidates`
//  to find a span it can insert verbatim.
//

import Foundation

enum QuotedSpanExtractor {
    /// Preferred spoken-quote length. Shorter than the entry cap so one
    /// sentence can sit next to the truncated body.
    static let maxChars = 180
    static let minChars = 24

    /// Returns a contiguous substring of `text`, or nil when nothing is clean.
    static func extract(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let first = candidates(from: trimmed).first {
            return first
        }

        if trimmed.count <= maxChars { return trimmed }
        let prefix = String(trimmed.prefix(maxChars))
        return trimmed.hasPrefix(prefix) ? prefix : nil
    }

    /// Every sentence of `text` inside the quote length bounds, in order.
    /// Each is a contiguous substring of the trimmed text; `extract` returns
    /// the first, and falls back to the whole text or a prefix when none fits.
    static func candidates(from text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return splitSentences(trimmed)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= minChars && $0.count <= maxChars && trimmed.contains($0) }
    }

    private static func splitSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        for char in text {
            current.append(char)
            if ".!?".contains(char) {
                sentences.append(current)
                current = ""
            }
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sentences.append(current)
        }
        return sentences
    }
}
