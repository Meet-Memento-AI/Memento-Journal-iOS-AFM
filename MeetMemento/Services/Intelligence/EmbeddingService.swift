//
//  EmbeddingService.swift
//  MeetMemento
//
//  On-device semantic embeddings for journal retrieval, replacing the server's
//  pgvector/Gemini embeddings. Uses Apple's NaturalLanguage sentence embeddings
//  (`NLEmbedding`, iOS 14+) — fully on-device, no network, no asset download.
//  Lets chat find relevant entries by meaning, not just literal keywords.
//
//  Entry vectors are cached twice (spec 029):
//  - In memory, keyed by entry id and invalidated when the entry's stable
//    content hash changes.
//  - On disk under Application Support/MementoEmbeddings, one compact binary
//    file per entry, so a relaunch does NOT re-embed the whole journal. The
//    files are derived journal data, so they get the same treatment as
//    LocalChatStore's transcripts: atomic writes with complete file
//    protection, purged on per-entry delete and on delete-everything
//    (spec 029 R8 — `removeEmbeddings`/`clearCache`).
//
//  Cache keys use a stable FNV-1a hash — `String.hashValue` is randomized per
//  process and can never key a persisted cache.
//
//  No `import FoundationModels` — pure NaturalLanguage/Accelerate/Swift.
//
//  (A future upgrade can swap in `NLContextualEmbedding` (iOS 17+, contextual
//  transformer, higher quality) behind this same interface, managing its
//  `hasAvailableAssets`/`requestEmbeddingAssets` lifecycle.)
//

import Accelerate
import Foundation
import NaturalLanguage

final class EmbeddingService: @unchecked Sendable {
    static let shared = EmbeddingService()

    private let lock = NSLock()
    private let fileManager = FileManager.default

    /// Where the per-entry vector files live (`<entry-uuid>.vec`).
    private let rootDirectory: URL

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

    /// Cache of pooled entry vectors + their L2 norms, keyed by entry id,
    /// invalidated on content-hash change. Norms are computed once at embed
    /// time so cosine needs only a dot product per (query, entry) pair.
    private var entryCache: [UUID: (hash: UInt64, vector: [Double], norm: Double)] = [:]

    /// Disk-cache load state (spec 029 Amendment A, audit F9). Guarded by
    /// `diskLoadGate`, NOT by `lock`: enumeration + decode of the .vec files
    /// happens with no lock held (see `ensureDiskCacheLoaded`), so this state
    /// needs its own gate that callers can wait on without stalling every
    /// unrelated cache lookup behind the first load.
    private enum DiskCacheState { case notLoaded, loading, loaded }
    private var diskCacheState: DiskCacheState = .notLoaded
    private let diskLoadGate = NSCondition()
    /// Bumped (under `lock`) by every purge (`removeEmbeddings` /
    /// `retainEmbeddings` / `clearCache`). An in-flight disk load snapshots it
    /// before enumerating and refuses to merge if it moved — otherwise a load
    /// racing a purge could resurrect vectors whose files were just deleted.
    private var purgeEpoch: UInt64 = 0

    /// Lowercased (title, text) per entry for the retriever's keyword scoring,
    /// invalidated by the same content hash as the vectors. In-memory ONLY —
    /// unlike vectors, this is the journal plaintext itself, which only ever
    /// touches disk encrypted (via JournalService), so it is rebuilt lazily
    /// each launch instead of being persisted alongside the vector files.
    private var lowercasedCache: [UUID: (hash: UInt64, title: String, text: String)] = [:]

    /// Small LRU of query vectors so repeated/follow-up questions skip
    /// NLEmbedding entirely. Keyed by the stable hash of the query text.
    private var queryCache: [UInt64: (vector: [Double], norm: Double)] = [:]
    private var queryOrder: [UInt64] = []   // least-recently-used first
    private static let queryCacheCapacity = 16

    /// `directory` is injectable for tests; defaults to Application Support
    /// (same pattern as `LocalChatStore.init(directory:)`).
    init(directory: URL? = nil) {
        rootDirectory = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MementoEmbeddings", isDirectory: true)
        try? fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    var isAvailable: Bool { embedderInfo != nil }

    // MARK: - Stable hashing

    /// FNV-1a 64-bit over UTF-8. Deterministic across launches (unlike
    /// `String.hashValue`), so it can key the persisted vector files.
    static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    /// Stable hash of an entry's (title, text) pair. The title's byte length is
    /// mixed in between the two fields so shifting characters across the
    /// title/text boundary can never produce the same hash (a plain
    /// concatenation like "title. text" would collide there).
    static func contentHash(title: String, text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in title.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
        var length = UInt64(title.utf8.count)
        for _ in 0..<8 {
            hash = (hash ^ (length & 0xFF)) &* 0x0000_0100_0000_01B3
            length >>= 8
        }
        for byte in text.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
        return hash
    }

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

    /// A pooled vector + norm for a *query*, memoized in the bounded LRU so a
    /// repeated or follow-up question doesn't re-run NLEmbedding.
    func embedQuery(_ text: String) -> (vector: [Double], norm: Double)? {
        let key = Self.stableHash(text)
        lock.lock()
        if let hit = queryCache[key] {
            if let index = queryOrder.firstIndex(of: key) {
                queryOrder.remove(at: index)
                queryOrder.append(key)
            }
            lock.unlock()
            return hit
        }
        lock.unlock()

        guard let vector = embed(text) else { return nil }
        let norm = Self.norm(of: vector)

        lock.lock()
        if queryCache[key] == nil {
            queryCache[key] = (vector, norm)
            queryOrder.append(key)
            if queryOrder.count > Self.queryCacheCapacity {
                queryCache.removeValue(forKey: queryOrder.removeFirst())
            }
        }
        lock.unlock()
        return (vector, norm)
    }

    /// A cached pooled vector for a journal entry — recomputed only when the
    /// content hash changes. Convenience wrapper that hashes `text` itself;
    /// callers that already hold a hash should use the two-cache-friendly
    /// `entryVector(id:text:contentHash:)` so the text is hashed once per turn.
    func embedEntry(id: UUID, text: String) -> [Double]? {
        entryVector(id: id, text: text, contentHash: Self.stableHash(text))?.vector
    }

    /// A cached pooled vector + precomputed norm for a journal entry. Checks
    /// memory first, then the lazily-loaded disk cache; embeds (and persists)
    /// only on a genuine miss or a content change.
    func entryVector(id: UUID, text: String, contentHash: UInt64) -> (vector: [Double], norm: Double)? {
        ensureDiskCacheLoaded()
        lock.lock()
        if let cached = entryCache[id], cached.hash == contentHash {
            lock.unlock()
            return (cached.vector, cached.norm)
        }
        lock.unlock()

        guard let vector = embed(text) else { return nil }
        let norm = storeEntryVector(vector, id: id, contentHash: contentHash)
        return (vector, norm)
    }

    /// The cached vector for an entry, if its content hash still matches —
    /// never embeds. Lets tests (and availability probes) inspect the cache on
    /// hosts without an NLEmbedding model.
    func cachedEntryVector(id: UUID, contentHash: UInt64) -> (vector: [Double], norm: Double)? {
        ensureDiskCacheLoaded()
        lock.lock()
        defer { lock.unlock() }
        guard let cached = entryCache[id], cached.hash == contentHash else { return nil }
        return (cached.vector, cached.norm)
    }

    /// Insert a known vector for an entry, caching and persisting it exactly
    /// as `entryVector` would after embedding. Seam for tests (which can't
    /// assume NLEmbedding assets) and for any future external embedder.
    /// Returns the norm computed for the vector.
    @discardableResult
    func storeEntryVector(_ vector: [Double], id: UUID, contentHash: UInt64) -> Double {
        let norm = Self.norm(of: vector)
        // Load the disk cache first so this insert is a fresh-this-launch
        // vector the merge's "in-memory wins" rule preserves, not one a later
        // load could race. (Also correct without this — the merge skips ids
        // already in memory — but keeping the order makes it obvious.)
        ensureDiskCacheLoaded()
        lock.lock()
        entryCache[id] = (contentHash, vector, norm)
        lock.unlock()

        // Write-through: one small file per entry means no index rewrite, no
        // debounce machinery, and single-entry blast radius on corruption.
        let data = Self.encodeVectorRecord(hash: contentHash, norm: norm, vector: vector)
        try? data.write(to: vectorFileURL(id), options: [.atomic, .completeFileProtection])
        return norm
    }

    // MARK: - Lowercased entry text (keyword-scoring cache)

    /// The entry's lowercased (title, text), cached under the same content
    /// hash as its vector. Caching the full lowercased strings (not token
    /// sets) keeps keyword scoring's substring-containment semantics
    /// bit-identical; the memory cost is roughly one extra copy of the journal
    /// text (~1 MB per thousand average entries), which is accepted.
    func lowercasedEntryText(id: UUID, contentHash: UInt64, title: String, text: String) -> (title: String, text: String) {
        lock.lock()
        if let cached = lowercasedCache[id], cached.hash == contentHash {
            lock.unlock()
            return (cached.title, cached.text)
        }
        lock.unlock()

        let loweredTitle = title.lowercased()
        let loweredText = text.lowercased()
        lock.lock()
        lowercasedCache[id] = (contentHash, loweredTitle, loweredText)
        lock.unlock()
        return (loweredTitle, loweredText)
    }

    // MARK: - Purge (spec 029 R8: derived journal data follows its source)

    /// Drop every cached derivative of the given entries — memory and disk.
    /// Call from the entry-delete path.
    func removeEmbeddings(for entryIds: [UUID]) {
        lock.lock()
        purgeEpoch &+= 1   // an in-flight disk load must not resurrect these
        for id in entryIds {
            entryCache.removeValue(forKey: id)
            lowercasedCache.removeValue(forKey: id)
        }
        lock.unlock()
        for id in entryIds {
            try? fileManager.removeItem(at: vectorFileURL(id))
        }
    }

    /// Garbage-collect: drop cached derivatives (memory and disk) for any
    /// entry NOT in `ids`. Safety net for delete paths that remove the entry
    /// file directly without going through `removeEmbeddings`.
    func retainEmbeddings(only ids: Set<UUID>) {
        lock.lock()
        purgeEpoch &+= 1   // an in-flight disk load must not resurrect the dropped set
        entryCache = entryCache.filter { ids.contains($0.key) }
        lowercasedCache = lowercasedCache.filter { ids.contains($0.key) }
        lock.unlock()

        guard let files = try? fileManager.contentsOfDirectory(at: rootDirectory, includingPropertiesForKeys: nil) else { return }
        for url in files where url.pathExtension == "vec" {
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                  !ids.contains(id) else { continue }
            try? fileManager.removeItem(at: url)
        }
    }

    /// Drop all cached vectors and derived text — memory AND disk (e.g. on
    /// sign-out / delete-everything).
    func clearCache() {
        lock.lock()
        purgeEpoch &+= 1   // an in-flight disk load must not merge after this wipe
        entryCache.removeAll()
        lowercasedCache.removeAll()
        queryCache.removeAll()
        queryOrder.removeAll()
        lock.unlock()

        diskLoadGate.lock()
        if diskCacheState != .loading {
            diskCacheState = .loaded   // nothing left on disk to load
        }
        // .loading: the in-flight loader marks .loaded itself when it
        // finishes; the epoch bump above already voids its merge.
        diskLoadGate.unlock()

        try? fileManager.removeItem(at: rootDirectory)
        try? fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Similarity (Accelerate)

    /// Cosine similarity in [-1, 1]. Returns 0 for degenerate vectors.
    static func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        let na = vDSP.sumOfSquares(a)
        let nb = vDSP.sumOfSquares(b)
        guard na > 0, nb > 0 else { return 0 }
        return vDSP.dot(a, b) / (na.squareRoot() * nb.squareRoot())
    }

    /// Cosine similarity using precomputed norms — one vDSP dot product per
    /// call, no per-pair norm recomputation. Returns 0 for degenerate inputs.
    static func cosineSimilarity(_ a: [Double], normA: Double, _ b: [Double], normB: Double) -> Double {
        guard a.count == b.count, !a.isEmpty, normA > 0, normB > 0 else { return 0 }
        return vDSP.dot(a, b) / (normA * normB)
    }

    /// L2 norm, computed once at embed time and stored alongside the vector.
    static func norm(of vector: [Double]) -> Double {
        guard !vector.isEmpty else { return 0 }
        return vDSP.sumOfSquares(vector).squareRoot()
    }

    // MARK: - Disk cache (per-entry binary records)

    private func vectorFileURL(_ id: UUID) -> URL {
        rootDirectory.appendingPathComponent("\(id.uuidString).vec")
    }

    /// Pull the on-disk vector cache into memory ahead of the first lookup —
    /// called from the prewarm chain so a chat send never pays the load.
    /// Idempotent and cheap once loaded (one condition-variable check), so it
    /// is safe to call on every chat onAppear. Spec 029 Amendment A.
    func warmDiskCache() {
        ensureDiskCacheLoaded()
    }

    /// Merge every readable on-disk record into `entryCache` (in-memory wins:
    /// it holds full-precision vectors from this launch), at most once per
    /// launch.
    ///
    /// Restructured for audit F9: directory enumeration + record decode used
    /// to run while HOLDING `lock`, stalling every embedding lookup behind
    /// the first caller's full-directory read. Now the files are read into a
    /// temporary map with no lock held, then merged under `lock`; concurrent
    /// callers wait on `diskLoadGate` (a `loading` flag guards against a
    /// double load) and the purge epoch keeps a racing purge from being
    /// undone by the merge.
    private func ensureDiskCacheLoaded() {
        diskLoadGate.lock()
        while diskCacheState == .loading { diskLoadGate.wait() }
        guard diskCacheState == .notLoaded else {   // .loaded — nothing to do
            diskLoadGate.unlock()
            return
        }
        diskCacheState = .loading
        diskLoadGate.unlock()

        lock.lock()
        let epochAtStart = purgeEpoch
        lock.unlock()

        // No lock held from here to the merge.
        var loaded: [UUID: (hash: UInt64, vector: [Double], norm: Double)] = [:]
        if let files = try? fileManager.contentsOfDirectory(at: rootDirectory, includingPropertiesForKeys: nil) {
            for url in files where url.pathExtension == "vec" {
                guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                      let data = try? Data(contentsOf: url),
                      let record = Self.decodeVectorRecord(data) else { continue }
                loaded[id] = (record.hash, record.vector, record.norm)
            }
        }

        lock.lock()
        if purgeEpoch == epochAtStart {
            for (id, record) in loaded where entryCache[id] == nil {
                entryCache[id] = record
            }
        }
        // else: a purge ran while we were reading — drop this pass's records
        // rather than resurrect deleted vectors. Anything legitimately still
        // on disk just re-embeds on demand (safe, merely un-cached).
        lock.unlock()

        diskLoadGate.lock()
        diskCacheState = .loaded
        diskLoadGate.broadcast()
        diskLoadGate.unlock()
    }

    /// Record layout (little-endian throughout):
    /// "MEV1" (4) | contentHash UInt64 (8) | norm Float64 (8) |
    /// count UInt32 (4) | count × Float32.
    /// Vectors are stored as Float32 — half the bytes of Float64, and the
    /// rounding (≈1e-7 relative) is far inside retrieval's tolerance.
    private static let recordMagic: [UInt8] = [0x4D, 0x45, 0x56, 0x31] // "MEV1"
    private static let recordHeaderSize = 24
    private static let maxVectorCount = 16_384

    static func encodeVectorRecord(hash: UInt64, norm: Double, vector: [Double]) -> Data {
        var data = Data(capacity: recordHeaderSize + vector.count * 4)
        data.append(contentsOf: recordMagic)
        appendLE(hash, to: &data)
        appendLE(norm.bitPattern, to: &data)
        appendLE(UInt32(vector.count), to: &data)
        for value in vector {
            appendLE(Float(value).bitPattern, to: &data)
        }
        return data
    }

    /// Strictly-validated decode; any malformed input returns `nil` and the
    /// caller just re-embeds — a corrupt cache file can never corrupt state.
    ///
    /// Bulk path (spec 029 Amendment A, audit F9): fields are read straight
    /// off the raw buffer with `loadUnaligned` instead of copying the whole
    /// record to `[UInt8]` and rebuilding each word a byte at a time through
    /// a reduce closure. The on-disk format ("MEV1", little-endian) and every
    /// validation rule are unchanged, so existing caches stay readable.
    static func decodeVectorRecord(_ data: Data) -> (hash: UInt64, norm: Double, vector: [Double])? {
        guard data.count >= recordHeaderSize else { return nil }
        return data.withUnsafeBytes { raw -> (hash: UInt64, norm: Double, vector: [Double])? in
            // `withUnsafeBytes` on a Data slice yields a buffer indexed from
            // 0 regardless of the slice's startIndex, so offsets below are
            // absolute within the record.
            guard raw.count >= recordHeaderSize,
                  raw[0] == recordMagic[0], raw[1] == recordMagic[1],
                  raw[2] == recordMagic[2], raw[3] == recordMagic[3] else { return nil }
            let hash = UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: 4, as: UInt64.self))
            let norm = Double(bitPattern: UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: 12, as: UInt64.self)))
            let count = Int(UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: 20, as: UInt32.self)))
            guard count > 0, count <= maxVectorCount,
                  raw.count == recordHeaderSize + count * 4,
                  norm.isFinite else { return nil }
            var vector = [Double](repeating: 0, count: count)
            var allFinite = true
            vector.withUnsafeMutableBufferPointer { out in
                for i in 0..<count {
                    let bits = UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: recordHeaderSize + i * 4, as: UInt32.self))
                    let value = Float(bitPattern: bits)
                    guard value.isFinite else { allFinite = false; return }
                    out[i] = Double(value)
                }
            }
            guard allFinite else { return nil }
            return (hash, norm, vector)
        }
    }

    private static func appendLE<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }

    // MARK: - Pooling

    /// Average of the per-sentence vectors for `text` (first ~800 chars).
    private static func pooledSentenceVector(for text: String, using embedder: NLEmbedding) -> [Double]? {
        // NLEmbedding is a different model with its own limits and no share of
        // the language model's context window.
        // budget-exempt: embedding input cap, not an LLM payload.
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
            .prefix(60) // budget-exempt: word-pooling width for NLEmbedding, not a model payload
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
