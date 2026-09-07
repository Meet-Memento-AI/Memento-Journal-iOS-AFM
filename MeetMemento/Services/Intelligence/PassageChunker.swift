//
//  PassageChunker.swift
//  MeetMemento
//
//  Spec 044 R1: split an entry into 2–4 sentence passages for embedding
//  and excerpting. Never splits inside a sentence. Pure NaturalLanguage —
//  no FoundationModels.
//

import Foundation
import NaturalLanguage

/// One embedded / excerptable slice of an entry.
struct Passage: Sendable, Equatable {
    let index: Int
    let text: String
    /// Inclusive-lower, exclusive-upper index into `ChunkedEntry.sentences`.
    let sentenceRange: Range<Int>
}

/// Result of chunking one journal entry.
struct ChunkedEntry: Sendable, Equatable {
    let passages: [Passage]
    let sentences: [String]
    let language: NLLanguage
}

enum PassageChunker {
    static let minChars = 120
    static let maxChars = 400

    private static let cacheLock = NSLock()
    private static var cache: [UInt64: ChunkedEntry] = [:]
    /// Soft cap so a huge journal cannot grow the cache without bound.
    /// budget-exempt: in-process chunk memo, not a model context window.
    private static let cacheLimit = 2_048

    /// Test seam — drop the in-process memo.
    static func resetCacheForTesting() {
        cacheLock.lock()
        cache.removeAll()
        cacheLock.unlock()
    }

    /// Tokenize `text` into sentences and merge them into 120–400 character
    /// passages. A single short entry (or one long sentence) becomes one
    /// passage. `title` is used only for language detection. When
    /// `contentHash` is supplied, identical entries reuse the chunked result
    /// so retrieve does not re-tokenize every send.
    static func chunk(title: String = "", text: String, contentHash: UInt64? = nil) -> ChunkedEntry {
        if let contentHash {
            cacheLock.lock()
            if let hit = cache[contentHash] {
                cacheLock.unlock()
                return hit
            }
            cacheLock.unlock()
        }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let language = detectLanguage(title: title, text: body)
        let sentences = tokenizeSentences(body)
        let passages = merge(sentences)
        let result = ChunkedEntry(passages: passages, sentences: sentences, language: language)
        if let contentHash {
            cacheLock.lock()
            if cache.count >= cacheLimit {
                cache.removeAll(keepingCapacity: true)
            }
            cache[contentHash] = result
            cacheLock.unlock()
        }
        return result
    }

    /// Best-scoring passage plus one neighboring sentence on each side,
    /// capped at `maxChars`.
    static func excerpt(
        sentences: [String],
        passage: Passage,
        maxChars: Int
    ) -> String {
        guard !sentences.isEmpty else {
            return String(passage.text.prefix(maxChars))
        }
        let start = max(0, passage.sentenceRange.lowerBound - 1)
        let end = min(sentences.count, passage.sentenceRange.upperBound + 1)
        let widened = sentences[start..<end]
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if widened.count <= maxChars { return widened }
        if passage.text.count <= maxChars { return passage.text }
        return String(passage.text.prefix(maxChars))
    }

    // MARK: - Language

    static func detectLanguage(title: String, text: String) -> NLLanguage {
        let blob = (title + " " + text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !blob.isEmpty else { return .undetermined }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(blob.prefix(2_000)))
        return recognizer.dominantLanguage ?? .undetermined
    }

    // MARK: - Sentences

    static func tokenizeSentences(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var sentences: [String] = []
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = trimmed
        tokenizer.enumerateTokens(in: trimmed.startIndex..<trimmed.endIndex) { range, _ in
            let piece = String(trimmed[range])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { sentences.append(piece) }
            return true
        }
        if sentences.isEmpty { return [trimmed] }
        return sentences
    }

    // MARK: - Merge

    /// Pack sentences into passages targeting `[minChars, maxChars]`.
    /// A sentence longer than `maxChars` stays whole (never split).
    static func merge(_ sentences: [String]) -> [Passage] {
        let cleaned = sentences
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return [] }

        let joined = cleaned.joined(separator: " ")
        if cleaned.count == 1 || joined.count <= minChars {
            return [Passage(index: 0, text: joined, sentenceRange: 0..<cleaned.count)]
        }

        var raw: [(range: Range<Int>, text: String)] = []
        var start = 0
        var buffer: [String] = []
        var chars = 0

        func flush() {
            guard !buffer.isEmpty else { return }
            let text = buffer.joined(separator: " ")
            raw.append((start..<(start + buffer.count), text))
            start += buffer.count
            buffer = []
            chars = 0
        }

        for sentence in cleaned {
            let extra = buffer.isEmpty ? sentence.count : sentence.count + 1
            if !buffer.isEmpty && chars + extra > maxChars {
                flush()
            }
            if buffer.isEmpty {
                buffer = [sentence]
                chars = sentence.count
            } else {
                buffer.append(sentence)
                chars += extra
            }
        }
        flush()

        if raw.count >= 2, raw[raw.count - 1].text.count < minChars {
            let last = raw.removeLast()
            let prev = raw.removeLast()
            let combined = prev.text + " " + last.text
            if combined.count <= maxChars {
                raw.append((prev.range.lowerBound..<last.range.upperBound, combined))
            } else {
                raw.append(prev)
                raw.append(last)
            }
        }

        return raw.enumerated().map { index, item in
            Passage(index: index, text: item.text, sentenceRange: item.range)
        }
    }
}
