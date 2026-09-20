//
//  QuotedSpanExtractor.swift
//  MeetMemento
//
//  Spec 037 follow-on / 019 archival quotes: pick one short contiguous
//  sentence from an entry for the evidence row's quoted field. Pure Swift —
//  no FoundationModels. The model is told to reproduce this field exactly.
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

        let sentences = splitSentences(trimmed)
        let candidates = sentences
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= minChars && $0.count <= maxChars }

        if let first = candidates.first, trimmed.contains(first) {
            return first
        }

        if trimmed.count <= maxChars { return trimmed }
        let prefix = String(trimmed.prefix(maxChars))
        return trimmed.hasPrefix(prefix) ? prefix : nil
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
