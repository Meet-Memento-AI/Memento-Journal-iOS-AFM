//
//  EntryRetriever.swift
//  MeetMemento
//
//  On-device retrieval for the Ask surface. Replaces the server's pgvector RAG.
//  Hybrid ranking = semantic similarity (on-device NaturalLanguage embeddings,
//  EmbeddingService) + keyword overlap + recency — so relevant entries surface
//  even when the question doesn't use their exact words. When a message is
//  general/open (no strong match), recent entries are supplied as *ambient*
//  context so chat can still converse about the person's life, rather than
//  refusing.
//
//  Whether retrieval runs at all — and with what query — is decided upstream
//  by TurnClassifier + RetrievalPolicy. Signals are relative: a match must
//  clear μ + k·σ of this corpus's cosines (NLEmbedding absolute cosines run
//  hot) or a real keyword bar, so casual messages no longer ground every
//  reply. All knobs live in RetrieverTuning.
//
//  No `import FoundationModels` — pure Swift + NaturalLanguage (via EmbeddingService).
//

import Foundation

/// One entry selected for context, with the ref number the model cites by.
struct RetrievedEntry: Sendable, Equatable {
    let ref: Int
    let id: UUID
    let date: Date
    let text: String   // already truncated for context
}

struct RetrievalResult: Sendable, Equatable {
    let entries: [RetrievedEntry]
    /// The dated, ref-numbered block to place in the prompt. Empty when there
    /// were no entries at all or the message was a trivial acknowledgement.
    let contextBlock: String
    /// True when the entries are recent-life background (no specific match) vs a
    /// direct topical answer — the prompt uses this to converse rather than cite.
    let isAmbient: Bool

    var isEmpty: Bool { entries.isEmpty }

    static let empty = RetrievalResult(entries: [], contextBlock: "", isAmbient: false)
}

/// Every retrieval knob in one place, injectable for tests.
struct RetrieverTuning: Sendable {
    /// Absolute cosine floor for a topical signal (guards tiny/degenerate corpora).
    var semanticFloorAbs = 0.30
    /// Signal requires cos ≥ μ + sigmaK·σ over the corpus (NLEmbedding absolute
    /// cosines run hot, so significance must be relative to this corpus).
    var sigmaK = 1.0
    /// High-bar (share turns) variants.
    var sigmaKHigh = 1.5
    var semanticFloorHigh = 0.40
    /// Keyword score needed to count as a signal (≈ a title hit + a body hit,
    /// or two distinct body terms). Replaces the old `keyword > 0`.
    var keywordSignalMin = 2.0
    var keywordSignalHigh = 3.0
    /// Current message dominates the semantic query; history only assists.
    var currentWeight = 0.75
    var historyWeight = 0.25
    /// Below this corpus size the σ statistics are meaningless — absolute floors only.
    var minCorpusForSigma = 5
    /// A signal must exceed the corpus mean by at least this margin even when
    /// σ ≈ 0 — otherwise a uniformly "hot" corpus (NLEmbedding scoring an
    /// unrelated query ~0.5 against everything) would let every entry through.
    var minSigmaMargin = 0.05
    /// Ambient background is capped tighter for high-bar (share) turns.
    var ambientCapHighBar = 3

    static let `default` = RetrieverTuning()
}

/// What to search with. Keywords always come from `currentMessage` only;
/// `historyContext` participates only as a separately-embedded assist vector.
struct RetrievalQuery: Sendable, Equatable {
    let currentMessage: String
    let historyContext: String?
    let highBar: Bool

    init(currentMessage: String, historyContext: String? = nil, highBar: Bool = false) {
        self.currentMessage = currentMessage
        self.historyContext = historyContext
        self.highBar = highBar
    }
}

/// How much journal evidence one retrieval may return.
///
/// Exists so the caps can come from the runtime context window (spec 017 R9)
/// instead of being fixed at compile time, without every call site having to
/// care. `.legacyDefault` is the pre-budget behaviour and stays the parameter
/// default, so existing callers and tests are unaffected.
struct RetrievalLimits: Equatable, Sendable {
    let maxEntries: Int
    let maxContentChars: Int

    /// The module's own tuned caps — the single source, not a copy.
    static let legacyDefault = RetrievalLimits(
        maxEntries: EntryRetriever.maxEntries,
        maxContentChars: EntryRetriever.maxContentChars
    )

    init(maxEntries: Int, maxContentChars: Int) {
        self.maxEntries = maxEntries
        self.maxContentChars = maxContentChars
    }

    init(budget: ContextBudget) {
        self.init(maxEntries: budget.maxRetrievedEntries, maxContentChars: budget.maxEntryChars)
    }

    /// Half the evidence, for a degraded route: the smaller model handles a
    /// narrower context better than a full one (technology/02 §8). Floored so a
    /// degraded reply is still grounded in something.
    func narrowed() -> RetrievalLimits {
        RetrievalLimits(maxEntries: max(2, maxEntries / 2), maxContentChars: maxContentChars)
    }
}

enum EntryRetriever {
    static let maxEntries = 7
    // Trimmed from 600 → 500: still enough of each entry to ground a reply,
    // while shrinking the journal-evidence block the model ingests per turn
    // (faster time-to-first-token). Tunable.
    static let maxContentChars = 500

    // Hybrid weights. Semantic dominates when available; keyword and recency
    // keep it grounded and break ties.
    private static let semanticWeight = 5.0
    private static let recencyWeight = 0.5

    /// The canonical text an entry is embedded under — must match what
    /// `retrieve` uses so the warm pass and the retrieval pass hit the same
    /// `EmbeddingService` cache key.
    static func embedText(for entry: Entry) -> String { "\(entry.title). \(entry.text)" }

    /// Precompute and cache every entry's embedding off the send path, so the
    /// first chat message doesn't pay the cold "embed all entries" cost. Cheap
    /// on repeat (the per-entry cache short-circuits unchanged entries). Call
    /// from a background context.
    static func warmEmbeddings(_ entries: [Entry]) {
        for entry in entries {
            _ = EmbeddingService.shared.embedEntry(id: entry.id, text: embedText(for: entry))
        }
    }

    private static let stopwords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "if", "then", "so", "to", "of", "in",
        "on", "at", "for", "with", "about", "as", "is", "are", "was", "were", "be",
        "been", "being", "do", "did", "does", "have", "has", "had", "i", "you", "me",
        "my", "your", "it", "this", "that", "what", "when", "where", "why", "how",
        "can", "could", "would", "should", "will", "just", "really", "very", "am"
    ]

    /// Select entries relevant to the query. Whether retrieval runs at all is
    /// decided upstream by TurnClassifier/RetrievalPolicy — this function only
    /// answers "which entries, and is the match real?".
    static func retrieve(
        _ query: RetrievalQuery,
        entries: [Entry],
        tuning: RetrieverTuning = .default,
        limits: RetrievalLimits = .legacyDefault
    ) -> RetrievalResult {
        let trimmed = query.currentMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if entries.isEmpty || trimmed.isEmpty { return .empty }

        let terms = tokenize(trimmed)
        let currentVector = EmbeddingService.shared.embed(trimmed)
        let historyVector = query.historyContext.flatMap { EmbeddingService.shared.embed($0) }
        let now = Date()

        // Pass 1: per-entry combined cosine (current-message dominated) so the
        // significance threshold can be computed over the whole corpus.
        struct Measured { let entry: Entry; let cosine: Double?; let keyword: Double }
        let measured: [Measured] = entries.map { entry in
            let keyword = keywordScore(entry: entry, terms: terms)
            var cosine: Double? = nil
            if let currentVector,
               let entryVector = EmbeddingService.shared.embedEntry(id: entry.id, text: embedText(for: entry)) {
                var value = EmbeddingService.cosineSimilarity(currentVector, entryVector) * tuning.currentWeight
                if let historyVector {
                    value += EmbeddingService.cosineSimilarity(historyVector, entryVector) * tuning.historyWeight
                } else {
                    // No history assist — don't penalize the current-only match.
                    value /= tuning.currentWeight
                }
                cosine = value
            }
            return Measured(entry: entry, cosine: cosine, keyword: keyword)
        }

        let cosines = measured.compactMap(\.cosine)
        let threshold = semanticThreshold(cosines: cosines, highBar: query.highBar, tuning: tuning)
        let keywordBar = query.highBar ? tuning.keywordSignalHigh : tuning.keywordSignalMin

        struct Scored { let entry: Entry; let score: Double; let hasSignal: Bool }
        let scored: [Scored] = measured.map { m in
            let semantic = m.cosine ?? 0.0
            let recency = recencyScore(entry: m.entry, now: now)
            let score = semantic * semanticWeight + m.keyword + recency * recencyWeight
            let hasSignal = (m.cosine.map { $0 >= threshold } ?? false) || m.keyword >= keywordBar
            return Scored(entry: m.entry, score: score, hasSignal: hasSignal)
        }
        .sorted { $0.score > $1.score }

        let strong = scored.filter(\.hasSignal).map(\.entry)
        let ordered: [Entry]
        let ambient: Bool
        let cap: Int
        if strong.isEmpty {
            // General / open message — hand the model recent life as background.
            ordered = entries.sorted { $0.createdAt > $1.createdAt }
            ambient = true
            cap = query.highBar ? min(tuning.ambientCapHighBar, limits.maxEntries) : limits.maxEntries
        } else {
            ordered = strong
            ambient = false
            cap = limits.maxEntries
        }

        // Diversify (drop near-duplicate bodies) and cap.
        var seen = Set<String>()
        var selected: [Entry] = []
        for entry in ordered {
            let fp = fingerprint(entry.text)
            if seen.insert(fp).inserted {
                selected.append(entry)
                if selected.count >= cap { break }
            }
        }
        if selected.isEmpty { return .empty }

        let retrieved = selected.enumerated().map { index, entry in
            RetrievedEntry(
                ref: index + 1,
                id: entry.id,
                date: entry.createdAt,
                text: String(entry.text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limits.maxContentChars))
            )
        }
        return RetrievalResult(entries: retrieved, contextBlock: buildContextBlock(retrieved, ambient: ambient), isAmbient: ambient)
    }

    // MARK: - Semantic significance (relative, testable)

    /// The cosine a match must clear to count as a real topical signal for THIS
    /// corpus: max(absolute floor, μ + k·σ) once the corpus is big enough for
    /// the statistics to mean anything. Pure — tests feed synthetic arrays.
    static func semanticThreshold(cosines: [Double], highBar: Bool, tuning: RetrieverTuning = .default) -> Double {
        let floorAbs = highBar ? tuning.semanticFloorHigh : tuning.semanticFloorAbs
        guard cosines.count >= tuning.minCorpusForSigma else {
            // Too few points for μ/σ — a slightly raised absolute floor.
            return floorAbs + 0.05
        }
        let mean = cosines.reduce(0, +) / Double(cosines.count)
        let variance = cosines.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(cosines.count)
        let sigma = variance.squareRoot()
        let k = highBar ? tuning.sigmaKHigh : tuning.sigmaK
        // The margin term guards the σ ≈ 0 degenerate case: a flat corpus has
        // no standout entry, no matter how hot its mean runs.
        return max(floorAbs, mean + max(k * sigma, tuning.minSigmaMargin))
    }

    // MARK: - Scoring

    private static func keywordScore(entry: Entry, terms: [String]) -> Double {
        guard !terms.isEmpty else { return 0 }
        let title = entry.title.lowercased()
        let text = entry.text.lowercased()
        var overlap = 0.0
        for term in terms {
            if text.contains(term) { overlap += 1 }
            if title.contains(term) { overlap += 1.5 }
        }
        return overlap
    }

    private static func recencyScore(entry: Entry, now: Date) -> Double {
        let ageDays = max(0, now.timeIntervalSince(entry.createdAt) / 86_400)
        return max(0.0, 1.0 - ageDays / 180.0)   // 1.0 today → 0.0 at 180d+
    }

    private static func tokenize(_ text: String) -> [String] {
        let words = text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        var seen = Set<String>()
        var result: [String] = []
        for word in words where word.count > 2 && !stopwords.contains(word) {
            if seen.insert(word).inserted { result.append(word) }
        }
        return result
    }

    private static func fingerprint(_ text: String) -> String {
        String(text.lowercased().filter { !$0.isWhitespace }.prefix(200))
    }

    // MARK: - Context block

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMMM d, yyyy"
        return f
    }()

    static func formattedDate(_ date: Date) -> String { dateFormatter.string(from: date) }

    private static func buildContextBlock(_ entries: [RetrievedEntry], ambient: Bool) -> String {
        guard !entries.isEmpty else { return "" }
        // The [ref N] labels below are an INTERNAL handle so the model can name
        // which entries it used in `citedRefs` — they are not a citation style
        // to reproduce in the reply. The header used to say "reference entries
        // by their [ref] number", which taught the model to write "ref 1" into
        // prose; nothing in the render path strips such markers, so they reached
        // the screen verbatim. Say plainly where the numbers belong instead.
        //
        // The per-entry line format below is load-bearing and must not change:
        // it is the addressing scheme `citedRefs` → `reconcileCitations` depends
        // on, and therefore what produces citations at all.
        let header = ambient
            ? "[Recent journal entries — background context. The person didn't ask about a specific one; use these to talk naturally, not to force citations.]"
            : "[Journal context. Each entry is tagged with a [ref] number for the citedRefs field only — never write these numbers, or any bracketed reference, in your reply. Refer to entries by their date or content.]"
        var lines = [header, ""]
        for entry in entries {
            lines.append("[ref \(entry.ref) | \(formattedDate(entry.date))] \(entry.text)")
        }
        lines.append("")
        lines.append("[End of journal context]")
        return lines.joined(separator: "\n")
    }
}
