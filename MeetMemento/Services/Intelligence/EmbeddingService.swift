//
//  EmbeddingService.swift
//  MeetMemento
//
//  On-device semantic embeddings for journal retrieval, replacing the server's
//  pgvector/Gemini embeddings. Uses Apple's NaturalLanguage sentence embeddings
//  (`NLEmbedding`, iOS 14+) — fully on-device, no network, no asset download.
//  Lets chat find relevant entries by meaning, not just literal keywords.
//
//  No `import FoundationModels` — pure NaturalLanguage/Swift.
//
//  (A future upgrade can swap in `NLContextualEmbedding` (iOS 17+, contextual
//  transformer, higher quality) behind this same interface, managing its
//  `hasAvailableAssets`/`requestEmbeddingAssets` lifecycle.)
//

import Foundation
import NaturalLanguage

final class EmbeddingService: @unchecked Sendable {
    static let shared = EmbeddingService()

    private let lock = NSLock()

    private enum Mode { case sentence, word }

    /// The best English embedder the OS provides: prefer sentence embeddings,
    /// fall back to word embeddings (pooled), and finally `nil` (retrieval then
    /// degrades to keyword scoring). Word embeddings are bundled on more
    /// configurations than sentence embeddings — including some simulators.
    private lazy var embedderInfo: (embedding: NLEmbedding, mode: Mode)? = {
        if let sentence = NLEmbedding.sentenceEmbedding(for: .english) { return (sentence, .sentence) }
        if let word = NLEmbedding.wordEmbedding(for: .english) { return (word, .word) }
        return nil
    }()

    /// Cache of pooled entry vectors, keyed by entry id, invalidated on text change.
    private var entryCache: [UUID: (hash: Int, vector: [Double])] = [:]

    var isAvailable: Bool { embedderInfo != nil }

    // MARK: - Embedding

    /// A pooled vector for arbitrary text (e.g. a query). Returns `nil` if
    /// nothing could be embedded.
    func embed(_ text: String) -> [Double]? {
        guard let info = embedderInfo else { return nil }
        switch info.mode {
        case .sentence: return Self.pooledSentenceVector(for: text, using: info.embedding)
        case .word:     return Self.pooledWordVector(for: text, using: info.embedding)
        }
    }

    /// A cached pooled vector for a journal entry. Recomputed only when the
    /// entry's text changes (hash mismatch).
    func embedEntry(id: UUID, text: String) -> [Double]? {
        let hash = text.hashValue
        lock.lock()
        if let cached = entryCache[id], cached.hash == hash {
            lock.unlock()
            return cached.vector
        }
        lock.unlock()

        guard let vector = embed(text) else { return nil }

        lock.lock()
        entryCache[id] = (hash, vector)
        lock.unlock()
        return vector
    }

    /// Drop cached vectors (e.g. on sign-out / delete-everything —
    /// AppStateStore.deleteEverything calls this; vectors are content-derived).
    func clearCache() {
        lock.lock(); entryCache.removeAll(); lock.unlock()
    }

    /// Test-inspectable cache size (delete-everything coverage).
    var cachedEntryCount: Int {
        lock.lock(); defer { lock.unlock() }
        return entryCache.count
    }

    // MARK: - Similarity

    /// Cosine similarity in [-1, 1]. Returns 0 for degenerate vectors.
    static func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        guard na > 0, nb > 0 else { return 0 }
        return dot / (na.squareRoot() * nb.squareRoot())
    }

    // MARK: - Pooling

    /// Average of the per-sentence vectors for `text` (first ~800 chars).
    private static func pooledSentenceVector(for text: String, using embedder: NLEmbedding) -> [Double]? {
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(800))
        guard !trimmed.isEmpty else { return nil }

        var vectors: [[Double]] = []
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = trimmed
        tokenizer.enumerateTokens(in: trimmed.startIndex..<trimmed.endIndex) { range, _ in
            let sentence = String(trimmed[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty, let v = embedder.vector(for: sentence) {
                vectors.append(v)
            }
            return vectors.count < 12
        }
        if vectors.isEmpty, let v = embedder.vector(for: trimmed) { return v }
        return mean(of: vectors)
    }

    /// Average of the per-word vectors for `text` (first ~60 content words) —
    /// the fallback when sentence embeddings aren't provisioned.
    private static func pooledWordVector(for text: String, using embedder: NLEmbedding) -> [Double]? {
        let words = text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count > 2 }
            .prefix(60)
        guard !words.isEmpty else { return nil }
        var vectors: [[Double]] = []
        for word in words {
            if let v = embedder.vector(for: word) { vectors.append(v) }
        }
        return mean(of: vectors)
    }

    private static func mean(of vectors: [[Double]]) -> [Double]? {
        guard let first = vectors.first else { return nil }
        if vectors.count == 1 { return first }
        var mean = [Double](repeating: 0, count: first.count)
        for v in vectors where v.count == mean.count {
            for i in 0..<mean.count { mean[i] += v[i] }
        }
        let n = Double(vectors.count)
        for i in 0..<mean.count { mean[i] /= n }
        return mean
    }
}
