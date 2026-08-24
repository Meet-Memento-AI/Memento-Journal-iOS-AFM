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
    /// Contiguous sentence copied from `text` when one is clean (spec 037 quotes).
    let quotedSpan: String?

    init(ref: Int, id: UUID, date: Date, text: String, quotedSpan: String? = nil) {
        self.ref = ref
        self.id = id
        self.date = date
        self.text = text
        self.quotedSpan = quotedSpan ?? QuotedSpanExtractor.extract(from: text)
    }
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
        // Spec 037 R7: the Ask block is 3–5 entries. The budget may still
        // compute a larger window-derived count; the UX cap is the retriever's.
        self.init(
            maxEntries: min(budget.maxRetrievedEntries, EntryRetriever.maxEntries),
            maxContentChars: budget.maxEntryChars
        )
    }

    /// Half the evidence, for a degraded route: the smaller model handles a
    /// narrower context better than a full one (technology/02 §8). Floored so a
    /// degraded reply is still grounded in something.
    func narrowed() -> RetrievalLimits {
        RetrievalLimits(maxEntries: max(2, maxEntries / 2), maxContentChars: maxContentChars)
    }
}

enum EntryRetriever {
    /// Spec 037 R7: at most 3–5 entries enter the Ask prompt. Floor of 3 is
    /// `ContextBudget.minRetrievedEntries`; this is the UX ceiling.
    static let maxEntries = 5
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
    /// `EmbeddingService` cache key (which is `contentHash(for:)`, computed
    /// once per entry per pass and shared with the keyword-scoring cache).
    static func embedText(for entry: Entry) -> String { "\(entry.title). \(entry.text)" }

    /// The stable invalidation key for everything cached about an entry's
    /// content (vector, norm, lowercased keyword text) — hashed over
    /// (title, text) separately rather than over `embedText`'s concatenation,
    /// so title/text boundary shifts can't collide. `warmed` is the
    /// generation-validated hash table from the last warm pass (audit F8):
    /// a hit skips re-hashing the entry's full title+text bytes; a miss (or a
    /// stale table — `warmedHashesIfCurrent` returns nil then) computes the
    /// identical FNV value directly, so results are bit-for-bit unchanged.
    private static func contentHash(for entry: Entry, warmed: [UUID: UInt64]?) -> UInt64 {
        if let hash = warmed?[entry.id] { return hash }
        return EmbeddingService.contentHash(title: entry.title, text: entry.text)
    }

    // MARK: - Warm pass + per-generation content-hash cache (spec 029 Amendment A)

    /// Guards `warmedHashes` and `warmedGeneration`.
    private static let warmLock = NSLock()
    /// entryID → content hash, as computed by the last COMMITTED warm pass.
    private static var warmedHashes: [UUID: UInt64] = [:]
    /// The `JournalService` corpus generation `warmedHashes` was computed
    /// against; nil until a warm pass commits. Stale ids from deleted entries
    /// may linger in the table between generations — harmless, they are never
    /// looked up (the entry is gone from the corpus) and the whole table is
    /// replaced on the next re-warm.
    private static var warmedGeneration: UInt64?

    /// `warmedHashes`, but only when it still describes the LIVE corpus —
    /// any mutation since the warm bumps the generation and the whole table
    /// is ignored (full per-turn rehash until the next warm re-runs, which
    /// every chat onAppear does). Never partially trusted: a single entry
    /// edit invalidates everything, because per-id staleness is undetectable
    /// without rehashing — exactly the work being avoided.
    private static func warmedHashesIfCurrent() -> [UUID: UInt64]? {
        warmLock.lock()
        guard let tagged = warmedGeneration, !warmedHashes.isEmpty else {
            warmLock.unlock()
            return nil
        }
        let hashes = warmedHashes
        warmLock.unlock()
        guard tagged == JournalService.shared.currentEntriesGeneration() else { return nil }
        return hashes
    }

    /// Precompute and cache every entry's embedding AND content hash off the
    /// send path, so the first chat message doesn't pay the cold "embed all
    /// entries" cost and steady-state turns don't re-hash the corpus
    /// (audit F8). Call from a background context.
    ///
    /// Idempotent-cheap (audit F6): called on every chat onAppear, so when
    /// the corpus generation hasn't moved since the last committed warm it
    /// returns immediately — no per-entry hashing, just the (post-first-call
    /// trivial) disk-cache check. Returns whether a full warm pass actually
    /// ran; `service`/`generation` are injectable for tests and default to
    /// the production singletons.
    @discardableResult
    static func warmEmbeddings(
        _ entries: [Entry],
        using service: EmbeddingService = .shared,
        generation explicitGeneration: UInt64? = nil
    ) -> Bool {
        let generation = explicitGeneration ?? JournalService.shared.currentEntriesGeneration()

        warmLock.lock()
        let alreadyWarm = warmedGeneration == generation
        warmLock.unlock()
        // Make sure the persisted vectors are in memory either way — a no-op
        // once loaded, and on the very first call it performs the disk-cache
        // load here, off the send path.
        service.warmDiskCache()
        if alreadyWarm { return false }

        var hashes = [UUID: UInt64](minimumCapacity: entries.count)
        for entry in entries {
            let hash = EmbeddingService.contentHash(title: entry.title, text: entry.text)
            hashes[entry.id] = hash
            _ = service.entryVector(id: entry.id, text: embedText(for: entry), contentHash: hash)
        }

        // Commit only if no mutation raced this pass — otherwise the hashes
        // may describe content the live corpus no longer has, and tagging
        // them with the newer generation would serve stale derived data.
        // (A save that lands before `entries` was even snapshotted by the
        // caller is outside what this guard can see; the window is the
        // microseconds between the caller's load and the generation read
        // above, and the next save heals it by bumping the generation.)
        let generationAfter = explicitGeneration ?? JournalService.shared.currentEntriesGeneration()
        warmLock.lock()
        if generation == generationAfter {
            warmedHashes = hashes
            warmedGeneration = generation
        }
        warmLock.unlock()
        return true
    }

    /// Test seam: forget all warm state so tests are order-independent.
    // periphery:ignore - test-only seam (EntryRetrieverConfidenceTests); retained deliberately
    static func resetWarmStateForTesting() {
        warmLock.lock()
        warmedHashes = [:]
        warmedGeneration = nil
        warmLock.unlock()
    }

    /// Test seam: the raw cached hash for an id (no generation check).
    // periphery:ignore - test-only seam (EntryRetrieverConfidenceTests); retained deliberately
    static func warmedHashForTesting(id: UUID) -> UInt64? {
        warmLock.lock()
        defer { warmLock.unlock() }
        return warmedHashes[id]
    }

    /// Words that carry no retrieval signal.
    ///
    /// The second block was added on 2026-08-23. IDF demotes a word that is
    /// common *as written*, but this journal's author writes "going", "getting"
    /// and "happened" far more often than the bare stems, so `go`, `get` and
    /// `happen` looked rare to IDF while contributing nothing but noise —
    /// "When did I go skiing last winter?" scored 5.0 against a corpus with no
    /// skiing in it, purely on `go` and `last`. `first`/`last`/`start` are safe
    /// to drop here because origin and recency are detected from the raw
    /// question by `seeksOrigin`, not from the keyword terms.
    private static let stopwords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "if", "then", "so", "to", "of", "in",
        "on", "at", "for", "with", "about", "as", "is", "are", "was", "were", "be",
        "been", "being", "do", "did", "does", "have", "has", "had", "i", "you", "me",
        "my", "your", "it", "this", "that", "what", "when", "where", "why", "how",
        "can", "could", "would", "should", "will", "just", "really", "very", "am",
        // High-frequency verbs and deictics whose inflected forms dominate the
        // text, so document frequency under-counts them.
        "go", "goes", "going", "went", "gone", "get", "gets", "getting", "got",
        "back", "into", "out", "up", "down", "over", "there", "here", "from", "by",
        "thing", "things", "make", "makes", "made", "tell", "tells", "told", "say",
        "says", "said", "like", "liked", "happen", "happens", "happened",
        "write", "writes", "wrote", "written", "first", "last", "day", "days",
        "we", "they", "them", "he", "she", "her", "his", "him", "our", "us", "all",
        "not", "no", "than", "some", "any", "more", "most", "much", "many", "one"
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

        let now = Date()
        // The date range the question named, if it named one. Its words are
        // subtracted from the keyword terms so "December" is scored as a date
        // and not also as a topic word.
        let window = QueryDateWindowParser.parse(trimmed, now: now)
        var terms = tokenize(trimmed)
        if let window {
            let dateWords = Set(tokenize(window.matchedText))
            terms.removeAll { dateWords.contains($0) }
        }
        // Query vectors come from the LRU (`embedQuery`), so a repeated or
        // follow-up question skips NLEmbedding entirely.
        let currentVector = EmbeddingService.shared.embedQuery(trimmed)
        let historyVector = query.historyContext.flatMap { EmbeddingService.shared.embedQuery($0) }

        // Pass 1: per-entry combined cosine (current-message dominated) so the
        // significance threshold can be computed over the whole corpus. The
        // content hash is resolved ONCE per entry here — from the warm pass's
        // generation-validated table when the corpus hasn't changed (the
        // steady state; no hashing at all), recomputed otherwise — and shared
        // by the vector cache and the keyword cache; norms are precomputed at
        // embed time, so each pair costs a single vDSP dot product.
        let warmedHashes = warmedHashesIfCurrent()
        let hashes = entries.map { contentHash(for: $0, warmed: warmedHashes) }
        // Keyword scoring is a corpus-wide pass now, not per-entry: a term's
        // weight depends on how many entries contain it, which cannot be known
        // one entry at a time. Same single scan over (entries × terms) as
        // before, with the document frequencies accumulated on the way through.
        let (keywordByEntry, documentFrequency) = Self.keywordScores(
            entries: entries, terms: terms, hashes: hashes
        )
        // Does the journal contain *any* of the words the question is about?
        //
        // "What have I said about my dog?" and "When did I go skiing last
        // winter?" are questions this corpus cannot answer, and the honest
        // reply is to say so. Semantic similarity alone will not say so — NL
        // embeddings score every entry warmly against any well-formed English
        // sentence, so μ + σ always crowns *something* and the reply came back
        // grounded in an unrelated entry, with citations. Zero lexical support
        // across every content term is the signal that nothing is on topic.
        //
        // With no date named this falls through to ambient rather than
        // `.empty`, deliberately: the person still gets recent life as
        // background and a conversational reply, and the `.noMatch` stance line
        // already tells the model to say plainly that it does not see the thing
        // they asked about. With a date named there is nothing left to offer,
        // and the windowed branch below returns `.empty`.
        let lexicallySupported = terms.isEmpty || documentFrequency.contains { $0 > 0 }
        struct Measured { let entry: Entry; let cosine: Double?; let keyword: Double }
        let measured: [Measured] = entries.enumerated().map { index, entry in
            let hash = hashes[index]
            let keyword = keywordByEntry[index]
            var cosine: Double? = nil
            if let currentVector,
               let entryVector = EmbeddingService.shared.entryVector(
                   id: entry.id, text: embedText(for: entry), contentHash: hash) {
                var value = EmbeddingService.cosineSimilarity(
                    currentVector.vector, normA: currentVector.norm,
                    entryVector.vector, normB: entryVector.norm
                ) * tuning.currentWeight
                if let historyVector {
                    value += EmbeddingService.cosineSimilarity(
                        historyVector.vector, normA: historyVector.norm,
                        entryVector.vector, normB: entryVector.norm
                    ) * tuning.historyWeight
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

        // An origin question drops the recency term rather than inverting it.
        // Inverting was measured (2026-08-23) and overshot: a *negative* recency
        // reward lets a weakly-matching very old entry outrank a strongly
        // matching one, so "when did Dario and I start talking again" walked
        // back to November when the answer was March. Relevance has to decide
        // which entries are candidates; age only decides between them, below.
        let origin = seeksOrigin(trimmed)
        struct Scored { let entry: Entry; let score: Double; let hasSignal: Bool; let touched: Bool }
        // The informative mass of the question: what an entry containing every
        // content word would score on the body alone.
        let queryWeight = documentFrequency
            .map { termWeight(documentFrequency: $0, corpus: entries.count) }
            .reduce(0, +)

        let scored: [Scored] = measured.map { m in
            let semantic = m.cosine ?? 0.0
            let recency = origin ? 0.0 : recencyScore(entry: m.entry, now: now)
            let score = semantic * semanticWeight + m.keyword + recency * recencyWeight
            // A named date range is a hard constraint, not a preference: an
            // entry outside the window cannot be the answer to "what did I
            // write in December", however well it scores on the words.
            let inWindow = window.map { $0.contains(m.entry.createdAt) } ?? true
            // An entry that carries essentially the whole question is a match
            // however modest its absolute score. `keywordSignalMin` is an
            // absolute bar — roughly "a title hit and a body hit" — and a
            // one-word question can never reach it: "When did I first say I was
            // burnt out?" reduces to *burnt*, whose single body hit scores 1.43
            // against a bar of 2.0, so the question fell through to ambient and
            // came back with the five most recent entries. Coverage says what
            // the absolute bar cannot: this entry contains what was asked.
            let covers = queryWeight > 0 && m.keyword >= queryWeight * 0.9
            let clears = (m.cosine.map { $0 >= threshold } ?? false)
                || m.keyword >= keywordBar || covers
            // Inside a named range the words have to land too. A semantic-only
            // hit put four unrelated 2025 entries behind "What did I write about
            // my brother in 2025?" — the right year, and not one of them
            // mentions him. When the person names both a period and a subject,
            // an entry from the period that never touches the subject is not
            // the answer.
            let lexicalWhereRequired = window == nil || terms.isEmpty || m.keyword > 0
            return Scored(entry: m.entry, score: score,
                          hasSignal: clears && inWindow && lexicalWhereRequired && lexicallySupported,
                          touched: inWindow && m.keyword > 0)
        }
        .sorted { $0.score > $1.score }

        let strong = scored.filter(\.hasSignal).map(\.entry)
        var ordered: [Entry]
        let ambient: Bool
        let cap: Int
        if strong.isEmpty, window != nil {
            // The question named a date range, and nothing in that range cleared
            // the bar. Recent-life ambient background is the wrong answer here —
            // it is what produced three citations for "When did I go skiing last
            // winter?" against a corpus with no skiing in it, and a March 2026
            // citation for "What did I write about my brother in 2025?".
            //
            // Entries in the window that at least touch the question's words are
            // still real evidence, so they are offered as a grounded (non-ambient)
            // result. When nothing in the window touches it, the honest answer is
            // nothing at all — `.empty` makes the stance `.noMatch` and leaves
            // `reconcileCitations` with nothing to cite.
            let touched = scored.filter(\.touched).map(\.entry)
            if touched.isEmpty { return .empty }
            ordered = origin ? touched.sorted { $0.createdAt < $1.createdAt } : touched
            ambient = false
            cap = limits.maxEntries
        } else if strong.isEmpty {
            // General / open message — hand the model recent life as background.
            ordered = entries.sorted { $0.createdAt > $1.createdAt }
            ambient = true
            cap = query.highBar ? min(tuning.ambientCapHighBar, limits.maxEntries) : limits.maxEntries
        } else {
            // On an origin question the answer is the earliest entry *that
            // actually matches* — not simply the oldest thing that shares a
            // word. So relevance picks the shortlist and age orders only that:
            // take the top matches by score, then put the earliest of them
            // first. Sorting the whole strong set by date instead walked back
            // to entries that merely mentioned the subject in passing.
            ordered = origin
                ? Array(strong.prefix(limits.maxEntries)).sorted { $0.createdAt < $1.createdAt }
                : strong
            ambient = false
            cap = limits.maxEntries
        }

        // Top up the prompt from the ranking when the bar left slots empty.
        //
        // The signal bar decides *whether* this turn is grounded; it was also,
        // accidentally, deciding *what* the model gets to see. μ + σ over a
        // 262-entry corpus is cleared by a handful of entries, so a question
        // whose answer sat just under it lost that entry altogether — not
        // ranked low, absent. Measured on the gold set: "When did I switch teams
        // at work?", "When did Sam and I break up?", "When did the crunch on
        // Atlas start?" and "What was I working on last December?" all had their
        // expected entry discarded this way while the prompt went out with
        // fewer entries than it had room for.
        //
        // Only tops up a result that already cleared the bar somewhere — an
        // ungrounded turn stays ungrounded, and ambient stays recent-life
        // background — and never crosses a named date window.
        if !ambient, ordered.count < cap {
            let taken = Set(ordered.map(\.id))
            let fill = scored.lazy
                .filter { candidate in
                    guard !taken.contains(candidate.entry.id) else { return false }
                    return window.map { $0.contains(candidate.entry.createdAt) } ?? true
                }
                .prefix(cap - ordered.count)
                .map(\.entry)
            ordered += origin ? fill.sorted { $0.createdAt < $1.createdAt } : Array(fill)
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

    /// Per-entry keyword scores for the whole corpus, IDF-weighted.
    ///
    /// Two things changed here on 2026-08-23, both measured against the
    /// 262-entry persona corpus:
    ///
    /// **1. Word boundaries.** `text.contains(term)` matched inside words, so
    /// `go` hit *going* and *ago*, `back` hit *background*, `into` hit almost
    /// every entry. The damage was not subtle: "When did I get back into
    /// running?" scored its expected entry **0.0** while an unrelated entry
    /// scored 5.0 on nothing but that noise, and "When did I go skiing last
    /// winter?" — a question this corpus cannot answer — scored 5.0 and
    /// produced three citations.
    ///
    /// **2. Rarity.** Every term counted the same, so *actually*, *thing* and
    /// *work* outvoted *Nonna*, *Atlas* and *pottery*. A term now contributes
    /// in proportion to how rare it is **in this corpus**, so the weighting
    /// adapts to the person's own vocabulary instead of a fixed word list.
    ///
    /// Same single scan over (entries × terms) as the per-entry version it
    /// replaces; document frequency is accumulated on the way through.
    static func keywordScores(
        entries: [Entry], terms: [String], hashes: [UInt64]
    ) -> (scores: [Double], documentFrequency: [Int]) {
        guard !terms.isEmpty, entries.count == hashes.count else {
            return (Array(repeating: 0, count: entries.count), Array(repeating: 0, count: terms.count))
        }
        // The lowercased copies are cached per entry (hash-invalidated), so
        // this does not re-lowercase the corpus on every turn.
        var bodyHits = [[Bool]](repeating: [Bool](repeating: false, count: terms.count),
                                count: entries.count)
        var titleHits = bodyHits
        var documentFrequency = [Int](repeating: 0, count: terms.count)

        for (index, entry) in entries.enumerated() {
            let (title, text) = EmbeddingService.shared.lowercasedEntryText(
                id: entry.id, contentHash: hashes[index], title: entry.title, text: entry.text
            )
            for (t, term) in terms.enumerated() {
                let inBody = containsWord(text, term)
                let inTitle = containsWord(title, term)
                bodyHits[index][t] = inBody
                titleHits[index][t] = inTitle
                if inBody || inTitle { documentFrequency[t] += 1 }
            }
        }

        let weights = documentFrequency.map { termWeight(documentFrequency: $0, corpus: entries.count) }
        let scores = entries.indices.map { index -> Double in
            var overlap = 0.0
            for t in terms.indices {
                if bodyHits[index][t] { overlap += weights[t] }
                if titleHits[index][t] { overlap += 1.5 * weights[t] }
            }
            return overlap
        }
        return (scores, documentFrequency)
    }

    /// Below this many entries the document frequencies are too noisy to mean
    /// anything, and the flat 1.0/1.5 weights are used unchanged — the same
    /// reasoning as `minCorpusForSigma` for the σ statistics.
    static let idfMinCorpus = 30

    /// A term's weight, scaled by how rare it is in this corpus.
    ///
    /// Normalised so a term appearing in ~5% of entries weighs exactly 1.0 —
    /// the old flat weight — which keeps `keywordSignalMin` meaning what it has
    /// always meant (roughly "a title hit and a body hit") and leaves small
    /// corpora bit-identical. Clamped at both ends: a near-universal word still
    /// counts for a little, and a word appearing once cannot clear the signal
    /// bar on its own.
    static func termWeight(documentFrequency: Int, corpus: Int) -> Double {
        guard corpus >= idfMinCorpus else { return 1.0 }
        guard documentFrequency > 0 else { return 0.0 }
        let idf = log(Double(corpus) / Double(1 + documentFrequency))
        let reference = log(Double(corpus) / (1.0 + 0.05 * Double(corpus)))
        guard reference > 0 else { return 1.0 }
        return min(2.0, max(0.15, idf / reference))
    }

    /// Does `haystack` contain `term` as a word?
    ///
    /// A short suffix is allowed so ordinary inflection still matches
    /// (*class* → *classes*, *apartment* → *apartments*), but only for terms
    /// long enough that the prefix is meaningful — which is what stops `go`
    /// from matching *going* and `back` from matching *background*. No stemmer:
    /// the trailing-character allowance covers the plural and participle cases
    /// that actually occur, and anything more aggressive re-introduces exactly
    /// the false matches this replaced.
    static func containsWord(_ haystack: String, _ term: String) -> Bool {
        guard !term.isEmpty, !haystack.isEmpty else { return false }
        if matchesWord(haystack, term) { return true }
        // The question may carry the inflected form and the entry the plain one
        // ("pottery *classes*" asked of "first pottery *class* tonight"), so the
        // term is also tried stemmed. Only trailing inflections, and only when
        // enough of the word survives for the prefix to still mean something.
        for suffix in ["ies", "es", "ing", "ed", "s"] where term.hasSuffix(suffix) {
            let stem = String(term.dropLast(suffix.count))
            let restored = suffix == "ies" ? stem + "y" : stem
            guard restored.count >= 4 else { continue }
            return matchesWord(haystack, restored)
        }
        return false
    }

    private static func matchesWord(_ haystack: String, _ term: String) -> Bool {
        // How much of a tail may follow and still be the same word. Three
        // letters for a full-length term, two for a three-letter one — enough
        // for "die" to reach *died*, which the journal writes while the
        // question says "when did my grandmother die" — and none at all below
        // that, which is what keeps "go" out of *going* and *ago*.
        let maxSuffix = term.count >= 4 ? 3 : (term.count == 3 ? 2 : 0)
        var searchStart = haystack.startIndex
        while let found = haystack.range(of: term, range: searchStart..<haystack.endIndex) {
            searchStart = found.upperBound
            // Must start a word.
            if found.lowerBound > haystack.startIndex {
                let before = haystack[haystack.index(before: found.lowerBound)]
                if before.isLetter || before.isNumber { continue }
            }
            // …and end one, give or take a short inflectional tail.
            var suffix = 0
            var cursor = found.upperBound
            while cursor < haystack.endIndex, suffix <= maxSuffix {
                let character = haystack[cursor]
                if !(character.isLetter || character.isNumber) { break }
                suffix += 1
                cursor = haystack.index(after: cursor)
            }
            if suffix <= maxSuffix { return true }
        }
        return false
    }

    /// Does this question ask when something *started*?
    ///
    /// "When did I first say I was burnt out?", "When did I start pottery
    /// classes?", "When did I get back into running?" — the answer is the
    /// **earliest** entry on the topic, and `recencyScore` actively argues for
    /// the opposite. Measured on the gold set 2026-08-23: seven of fifteen
    /// wrong-citation failures were this exact shape, every one of them citing
    /// a later entry about the right subject —
    ///   "when did I start pottery classes?"  → cited May and July, expected January
    ///   "when did I get back into running?"  → cited March,        expected November
    ///   "when did I first say I was burnt out?" → cited March,     expected January
    ///
    /// Kept deliberately narrow: it must fire on origin questions and stay off
    /// "what did I write *last* week", where recency is the whole point.
    static func seeksOrigin(_ query: String) -> Bool {
        let lower = query.lowercased()
        // A recency cue always wins — "when did I last go running" is not an
        // origin question even though it shares the "when did I" opener.
        for recent in ["last week", "last month", "lately", "recently",
                       "most recent", "last time", "these days"] {
            if lower.contains(recent) { return false }
        }
        for cue in ["first said", "first say", "first time", "first mention",
                    "first wrote", "first write", "start", "started", "starting",
                    "begin", "began", "beginning", "get back into", "got back into",
                    "take up", "took up", "originally", "at the beginning"] {
            if lower.contains(cue) { return true }
        }
        return false
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
        // budget-exempt: dedup fingerprint length; never enters a prompt.
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

    static func contextBlock(for entries: [RetrievedEntry], ambient: Bool) -> String {
        buildContextBlock(entries, ambient: ambient)
    }

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
            if let quote = entry.quotedSpan, !quote.isEmpty {
                lines.append("quoted: \"\(quote)\"")
            }
        }
        lines.append("")
        lines.append("[End of journal context]")
        return lines.joined(separator: "\n")
    }
}
