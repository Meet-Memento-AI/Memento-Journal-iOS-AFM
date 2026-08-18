
import Foundation

/// On-device journal persistence (no accounts, spec 023). Entries live
/// exclusively in encrypted local storage — this service has no backend
/// dependency, so there is no network or API key in the path. The
/// server-backed CRUD that used to live here was dead code from the
/// pre-023 architecture and has been removed.
class JournalService {
    static let shared = JournalService()

    /// Internal (not private) so tests can decrypt what this instance wrote
    /// via its own injected `EncryptionService`, without a Keychain-backed
    /// round trip through `.shared`. Defaults to the shared, real-Keychain
    /// instance in production.
    let encryptionService: EncryptionService

    init(encryptionService: EncryptionService = .shared) {
        self.encryptionService = encryptionService
    }

    // MARK: - Local-Only Storage (no accounts, spec 023)

    /// Everything needed to fully reconstruct an entry from local storage
    /// alone. `saveEncryptedLocally`'s content-only payload was originally
    /// just a cache — title/dates lived on the server row. With no server
    /// at all, this is now the sole persistence format for an entry: title
    /// and dates round-trip inside the same encrypted blob as the content.
    private struct LocalEntryEnvelope: Codable {
        let title: String
        let content: String
        let createdAt: Date
        let updatedAt: Date
        /// Whether this entry has a photo in `PhotoStorage`. Added after the
        /// envelope shipped, so every already-on-disk envelope lacks this key —
        /// a synthesized `Decodable` throws on a missing key even with a
        /// default value, so decoding is implemented explicitly below.
        let hasPhoto: Bool

        init(title: String, content: String, createdAt: Date, updatedAt: Date, hasPhoto: Bool) {
            self.title = title
            self.content = content
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.hasPhoto = hasPhoto
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decode(String.self, forKey: .title)
            content = try container.decode(String.self, forKey: .content)
            createdAt = try container.decode(Date.self, forKey: .createdAt)
            updatedAt = try container.decode(Date.self, forKey: .updatedAt)
            hasPhoto = try container.decodeIfPresent(Bool.self, forKey: .hasPhoto) ?? false
        }
    }

    /// Saves an entry's complete data (title, content, dates) to local
    /// encrypted storage. This is the only place an entry is persisted now
    /// — there is no server round trip to fall back on.
    @discardableResult
    func saveEntryLocally(
        entryId: UUID,
        title: String,
        content: String,
        createdAt: Date,
        updatedAt: Date,
        hasPhoto: Bool = false
    ) -> Bool {
        let envelope = LocalEntryEnvelope(title: title, content: content, createdAt: createdAt, updatedAt: updatedAt, hasPhoto: hasPhoto)
        guard let json = try? JSONEncoder().encode(envelope),
              let jsonString = String(data: json, encoding: .utf8),
              let encrypted = encryptionService.encrypt(jsonString) else {
            AppLogger.log("⚠️ [JournalService] Failed to encrypt entry for local storage: \(entryId)")
            return false
        }
        do {
            try LocalJournalStorage.shared.saveEncrypted(entryId: entryId, encryptedData: encrypted)
            noteMutation()
            return true
        } catch {
            AppLogger.log("⚠️ [JournalService] Failed to save entry locally: \(error)")
            return false
        }
    }

    /// Deletes an entry's local file AND every content-derived cache of it —
    /// the embedding vector on disk in particular (spec 029 R8: derived
    /// journal data follows its source). Delete call sites should route here
    /// rather than calling `LocalJournalStorage.deleteEncrypted` directly;
    /// the id-set guard in `loadAllEntriesLocally` keeps direct deletions
    /// correct, but only this path purges the persisted embedding.
    func deleteEntryLocally(entryId: UUID) {
        LocalJournalStorage.shared.deleteEncrypted(entryId: entryId)
        EmbeddingService.shared.removeEmbeddings(for: [entryId])
        noteMutation()
    }

    /// Loads and decrypts every entry stored locally — the sole source of
    /// truth for the journal now that there's no account/server.
    ///
    /// Handles two on-disk formats:
    /// - Envelope (current): the decrypted string is `LocalEntryEnvelope` JSON.
    /// - Legacy (pre-local-only builds): the decrypted string is the raw entry
    ///   content — title/dates lived on the server row or in the pending-sync
    ///   queue, never in this file. Legacy entries are recovered best-effort
    ///   and migrated to envelope format on first read, so the fallback only
    ///   ever runs once per entry.
    ///
    /// It also handles two *key* schemes, by the same lazy per-entry rule:
    /// content encrypted under the current data key, and legacy content
    /// encrypted under PBKDF2(`legacyPIN`). Anything read via the legacy key is
    /// immediately rewritten under the data key, so the fallback runs at most
    /// once per entry and a crash mid-migration only leaves the remainder to be
    /// picked up next launch. Pass `legacyPIN: nil` once no legacy content can
    /// exist.
    func loadAllEntriesLocally(legacyPIN: String?) -> [Entry] {
        if let cached = cachedEntriesIfFresh(legacyPIN: legacyPIN) { return cached }

        // In-flight dedupe (spec 029 Amendment A, audit F7): a cold cache can
        // be hit concurrently — the prewarm chain's detached task and the
        // journal view's appear-load both land here at launch — and each used
        // to pay a full AES-GCM decrypt of the corpus. The signature stays
        // synchronous by design (call sites are sync), so the dedupe is a
        // condition wait: the first caller through takes the full-load slot;
        // any caller arriving while it runs blocks on the condition, then
        // re-checks the cache the finished load just armed and returns it
        // without decrypting anything. A waiter whose cache re-check still
        // misses (e.g. its `legacyPIN` differs and failed ids must be
        // retried, or a mutation raced in) simply takes the slot itself.
        coldLoadGate.lock()
        while coldLoadInFlight { coldLoadGate.wait() }
        coldLoadInFlight = true
        coldLoadGate.unlock()
        defer {
            // Runs after `performFullLoad` has returned (and armed the
            // cache), so woken waiters see the fresh cache.
            coldLoadGate.lock()
            coldLoadInFlight = false
            coldLoadGate.broadcast()
            coldLoadGate.unlock()
        }

        if let cached = cachedEntriesIfFresh(legacyPIN: legacyPIN) { return cached }
        return performFullLoad(legacyPIN: legacyPIN)
    }

    /// The two cheap cache checks, extracted so `loadAllEntriesLocally` can
    /// run them both before AND after waiting out a concurrent cold load.
    /// Returns nil when a full decrypt pass is required.
    private func cachedEntriesIfFresh(legacyPIN: String?) -> [Entry]? {
        let ids = LocalJournalStorage.shared.allStoredEntryIds()

        // Fast path (every chat send lands here): reuse the cached decrypted
        // set when no mutation has gone through this service since it was
        // built (monotonic change counter) AND the on-disk id set still
        // matches. The id-set check exists because deletes still reach
        // LocalJournalStorage directly from the view models, so the counter
        // alone can't see them. This skips the per-entry stat that
        // `cacheSignature` pays; that signature remains the cold-start /
        // counter-mismatch validator below. Decrypted content is
        // PIN-independent, so the cache is valid across PIN changes — only
        // previously-FAILED ids care about the PIN (see shouldRetryFailedEntries).
        entriesCacheLock.lock()
        if let cache = entriesCache,
           Self.isEntriesCacheReusable(
               cachedCounter: cache.counter, currentCounter: changeCounter,
               cachedIds: cache.allIds, storedIds: Set(ids)),
           !Self.shouldRetryFailedEntries(
               failedMtimes: cache.failedMtimes,
               currentMtime: { LocalJournalStorage.shared.modificationDate(entryId: $0) },
               failedPIN: cache.failedPIN, currentPIN: legacyPIN) {
            let entries = cache.entries
            entriesCacheLock.unlock()
            return entries
        }
        entriesCacheLock.unlock()

        // Cold start or counter mismatch: fall back to the full signature
        // (ids + modification dates), which busts automatically on any
        // add/edit/delete, before paying for a full re-decrypt.
        let signature = Self.cacheSignature(for: ids)
        entriesCacheLock.lock()
        if let cache = entriesCache, cache.signature == signature,
           !Self.shouldRetryFailedEntries(
               failedMtimes: cache.failedMtimes,
               currentMtime: { LocalJournalStorage.shared.modificationDate(entryId: $0) },
               failedPIN: cache.failedPIN, currentPIN: legacyPIN) {
            // Re-arm the counter fast path for the next call.
            entriesCache = cache.withCounter(changeCounter)
            let entries = cache.entries
            entriesCacheLock.unlock()
            return entries
        }
        entriesCacheLock.unlock()
        return nil
    }

    /// The full decrypt pass. Only ever runs holding the `coldLoadGate`
    /// full-load slot (see `loadAllEntriesLocally`), so at most one corpus
    /// decrypt is in flight at a time.
    private func performFullLoad(legacyPIN: String?) -> [Entry] {
        // Re-read the id set: this may run after waiting out another load,
        // and the signature below must describe what THIS pass decrypts.
        let ids = LocalJournalStorage.shared.allStoredEntryIds()
        let signature = Self.cacheSignature(for: ids)

        entriesCacheLock.lock()
        fullLoadCount &+= 1
        entriesCacheLock.unlock()

        // Full reload — a good moment to garbage-collect persisted embedding
        // vectors of entries that no longer exist on disk (covers delete
        // paths that bypass `deleteEntryLocally`). `ids` includes entries that
        // fail to decrypt below, so this never over-purges.
        EmbeddingService.shared.retainEmbeddings(only: Set(ids))

        // Decrypt failures are tracked per id (with the mtime seen at failure)
        // so the good subset can still be cached; a failed id is retried only
        // when its file changes, the offered PIN changes, or next launch.
        // A file that can't even be READ is different: that can be transient
        // environment state (protected data unavailable) invisible to those
        // triggers, so it disables caching for this pass entirely.
        var failed: [UUID: Date] = [:]
        var hadUnreadableFile = false

        // Counter snapshot for the cache-write below: the lazy migrations in
        // this loop bump the counter themselves (they go through
        // `saveEntryLocally`), which is fine — the cache holds exactly what
        // they wrote. But a CONCURRENT save from another thread also bumps
        // it, and caching under that value would let stale content pass the
        // fast path. So self-bumps are counted and any unexplained bump
        // refuses to arm the fast path (the signature check adjudicates).
        entriesCacheLock.lock()
        let counterAtStart = changeCounter
        entriesCacheLock.unlock()
        var selfMutations: UInt64 = 0

        let entries: [Entry] = ids.compactMap { id -> Entry? in
            guard let data = LocalJournalStorage.shared.loadEncrypted(entryId: id) else {
                hadUnreadableFile = true
                return nil
            }
            guard let read = encryptionService.decryptMigrating(data, legacyPIN: legacyPIN) else {
                failed[id] = LocalJournalStorage.shared.modificationDate(entryId: id) ?? .distantPast
                return nil
            }
            let decrypted = read.text

            if let json = decrypted.data(using: .utf8),
               let envelope = try? JSONDecoder().decode(LocalEntryEnvelope.self, from: json) {
                if read.needsRewrite {
                    // Correct envelope, legacy key — rewrite under the data key.
                    if saveEntryLocally(entryId: id, title: envelope.title, content: envelope.content,
                                        createdAt: envelope.createdAt, updatedAt: envelope.updatedAt,
                                        hasPhoto: envelope.hasPhoto) {
                        selfMutations &+= 1
                    }
                    AppLogger.log("🔐 [JournalService] Re-encrypted entry under the data key: \(id)")
                }
                return Entry(
                    id: id,
                    title: envelope.title,
                    text: envelope.content,
                    createdAt: envelope.createdAt,
                    updatedAt: envelope.updatedAt,
                    hasPhoto: envelope.hasPhoto
                )
            }

            // Legacy format: `decrypted` is the raw content itself. Titles
            // used to live on a server row (and later in a pending-sync
            // queue). Both are gone; recover a title from the first line
            // and a date from the file mtime, then rewrite as an envelope
            // so this path never runs again.
            let title = Self.fallbackTitle(fromContent: decrypted)
            let timestamp = LocalJournalStorage.shared.modificationDate(entryId: id) ?? Date()

            if saveEntryLocally(entryId: id, title: title, content: decrypted,
                                createdAt: timestamp, updatedAt: timestamp, hasPhoto: false) {
                selfMutations &+= 1
            }
            AppLogger.log("📁 [JournalService] Migrated legacy-format entry to envelope: \(id)")

            return Entry(
                id: id, title: title, text: decrypted,
                createdAt: timestamp, updatedAt: timestamp, hasPhoto: false
            )
        }

        // Cache the successfully-decrypted subset even when some ids failed —
        // one corrupt or key-mismatched file must not force a full re-decrypt
        // on every chat send. The failure is NOT keyed to an unchanging
        // signature (the old hazard: loading once before PIN delivery cached
        // an empty journal forever): each failed id carries its mtime and the
        // PIN in effect, and `shouldRetryFailedEntries` forces a retry the
        // moment either changes — plus every cold start, since this cache is
        // in-memory only. Only an unreadable *file* (possible transient
        // protected-data state, invisible to those triggers) skips caching.
        if hadUnreadableFile {
            AppLogger.log("⚠️ [JournalService] Some entry files were unreadable (not just undecryptable) — not caching this pass")
        } else {
            if !failed.isEmpty {
                AppLogger.log("⚠️ [JournalService] \(failed.count)/\(ids.count) entries undecryptable with the current key material — caching the readable subset; failures retry on file/PIN change or next launch")
            }
            entriesCacheLock.lock()
            // Arm the fast path only when every bump since the snapshot is
            // one of this load's own migrations; otherwise store a value the
            // (monotonic) counter can never equal again, so the next call
            // falls through to the signature check.
            let expected = counterAtStart &+ selfMutations
            let armedCounter = changeCounter == expected ? changeCounter : changeCounter &- 1
            entriesCache = EntriesCache(
                signature: signature,
                counter: armedCounter,
                entries: entries,
                failedMtimes: failed,
                failedPIN: legacyPIN
            )
            entriesCacheLock.unlock()
        }
        return entries
    }

    // MARK: - Decrypted-entries cache

    /// Serializes cold full-decrypt passes (spec 029 Amendment A): while one
    /// caller decrypts the corpus, concurrent callers wait here instead of
    /// decrypting it again. Guards `coldLoadInFlight` only — never held while
    /// decrypting (the slot flag is what excludes, the condition just parks
    /// waiters), and never nested with `entriesCacheLock`.
    private let coldLoadGate = NSCondition()
    /// Whether a full-decrypt pass currently holds the slot. Guarded by `coldLoadGate`.
    private var coldLoadInFlight = false
    /// How many full decrypt passes have run — test seam for the dedupe
    /// (concurrent cold callers must produce ONE pass). Guarded by
    /// `entriesCacheLock`.
    // periphery:ignore - test-only observability for JournalServiceTests; retained deliberately
    private(set) var fullLoadCount: UInt64 = 0

    /// Guards `entriesCache` AND `changeCounter`.
    private let entriesCacheLock = NSLock()
    /// Cache of the decrypted entry set. Validated cheaply per call by the
    /// change counter + on-disk id set; the stat signature is only recomputed
    /// on cold start or after a counter mismatch.
    private var entriesCache: EntriesCache?
    /// Monotonic mutation counter: bumped by every write that goes through
    /// this service (save/update/migrate/delete/invalidate). "Unchanged since
    /// the cache was built" is the per-send fast-path validity check.
    private var changeCounter: UInt64 = 0

    private struct EntriesCache {
        let signature: String
        let counter: UInt64
        let entries: [Entry]
        /// Ids that failed to DECRYPT, with the file mtime observed at failure
        /// (`.distantPast` when unknown) — the retry trigger.
        let failedMtimes: [UUID: Date]
        /// The `legacyPIN` in effect when the failures were recorded — a
        /// different PIN on a later call means new key material, so failed
        /// ids must be retried. (The PIN already lives in SecurityService's
        /// Keychain; holding it here adds no new exposure.)
        let failedPIN: String?
        /// Everything on disk when the cache was built — decrypted + failed.
        let allIds: Set<UUID>

        init(signature: String, counter: UInt64, entries: [Entry], failedMtimes: [UUID: Date], failedPIN: String?) {
            self.signature = signature
            self.counter = counter
            self.entries = entries
            self.failedMtimes = failedMtimes
            self.failedPIN = failedPIN
            self.allIds = Set(entries.map(\.id)).union(failedMtimes.keys)
        }

        /// Same cache, re-armed for the counter fast path.
        func withCounter(_ counter: UInt64) -> EntriesCache {
            EntriesCache(signature: signature, counter: counter, entries: entries,
                         failedMtimes: failedMtimes, failedPIN: failedPIN)
        }
    }

    /// Records a mutation that went through this service.
    private func noteMutation() {
        entriesCacheLock.lock(); changeCounter &+= 1; entriesCacheLock.unlock()
    }

    /// The corpus generation: the current value of the monotonic mutation
    /// counter (spec 029 Amendment A, audit F8). Exposed so callers that
    /// cache per-entry CONTENT-derived data (EntryRetriever's content-hash
    /// table) can tag their cache with the generation it was computed against
    /// and invalidate wholesale when it moves. Every content change bumps it
    /// (add/edit/migrate all route through `saveEntryLocally`); deletes that
    /// bypass this service leave it untouched, which is safe for that use —
    /// a delete cannot alter the content hash of any surviving entry.
    func currentEntriesGeneration() -> UInt64 {
        entriesCacheLock.lock(); defer { entriesCacheLock.unlock() }
        return changeCounter
    }

    /// Clears the decrypted-entries cache (e.g. on delete-everything / sign-out).
    func invalidateEntriesCache() {
        entriesCacheLock.lock()
        entriesCache = nil
        changeCounter &+= 1
        entriesCacheLock.unlock()
    }

    /// Pure decision: may the cached decrypted set be reused without touching
    /// any per-entry file attributes? True when no mutation went through this
    /// service since the cache was built AND the on-disk id set is unchanged
    /// (the id set catches deletes made directly against LocalJournalStorage).
    static func isEntriesCacheReusable(
        cachedCounter: UInt64, currentCounter: UInt64,
        cachedIds: Set<UUID>, storedIds: Set<UUID>
    ) -> Bool {
        cachedCounter == currentCounter && cachedIds == storedIds
    }

    /// Pure decision: must previously-undecryptable entries be retried now?
    /// Yes when the offered key material changed (different `legacyPIN` than
    /// at failure time) or any failed file was rewritten since (mtime moved —
    /// lazy migration or an out-of-band edit). An empty failure set never
    /// forces a retry.
    static func shouldRetryFailedEntries(
        failedMtimes: [UUID: Date],
        currentMtime: (UUID) -> Date?,
        failedPIN: String?, currentPIN: String?
    ) -> Bool {
        guard !failedMtimes.isEmpty else { return false }
        if failedPIN != currentPIN { return true }
        return failedMtimes.contains { id, mtime in
            (currentMtime(id) ?? .distantPast) != mtime
        }
    }

    private static func cacheSignature(for ids: [UUID]) -> String {
        ids.sorted { $0.uuidString < $1.uuidString }
            .map { id in
                let mtime = LocalJournalStorage.shared.modificationDate(entryId: id)?.timeIntervalSince1970 ?? 0
                return "\(id.uuidString):\(mtime)"
            }
            .joined(separator: "|")
    }

    /// Best-effort title for a legacy entry with no recoverable title: its
    /// first non-empty line, truncated, or "Untitled".
    private static func fallbackTitle(fromContent content: String) -> String {
        let firstLine = content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard !firstLine.isEmpty else { return "Untitled" }
        return firstLine.count > 50 ? String(firstLine.prefix(50)) + "…" : firstLine
    }

}
