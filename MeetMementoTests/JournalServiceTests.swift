import XCTest
@testable import MeetMemento

/// Coverage note: the journal is on-device only, so there is no
/// CRUD-over-network path to test. What's covered here is
/// local envelope persistence, legacy-file migration to envelopes,
/// and the retry/error classification logic `withRetry` depends on.
final class JournalServiceTests: XCTestCase {
    private func makeService() -> JournalService {
        JournalService(encryptionService: EncryptionService(keychain: InMemoryKeychainStore()))
    }

    override func tearDown() {
        LocalJournalStorage.shared.clearAll()
        super.tearDown()
    }

    // MARK: - Legacy-format migration (pre-local-only builds)

    /// Writes an entry file in the OLD on-disk format: the encrypted payload
    /// is the raw content string, not a `LocalEntryEnvelope` JSON blob. This
    /// is exactly what the deleted `saveEncryptedLocally` used to produce.
    private func writeLegacyFormatFile(service: JournalService, entryId: UUID, content: String, pin: String) {
        guard let encrypted = service.encryptionService.encrypt(content, withPIN: pin) else {
            return XCTFail("failed to encrypt legacy fixture")
        }
        try? LocalJournalStorage.shared.saveEncrypted(entryId: entryId, encryptedData: encrypted)
    }

    func test_loadAllEntriesLocally_legacyFile_noQueueOp_fallsBackToFirstLine() {
        let service = makeService()
        let entryId = UUID()
        writeLegacyFormatFile(service: service, entryId: entryId,
                              content: "A morning thought\nwith more detail below", pin: "4829")

        let all = service.loadAllEntriesLocally(legacyPIN: "4829")
        guard let entry = all.first(where: { $0.id == entryId }) else {
            return XCTFail("legacy entry must not be dropped")
        }
        XCTAssertEqual(entry.title, "A morning thought")
        XCTAssertEqual(entry.text, "A morning thought\nwith more detail below")
    }

    func test_loadAllEntriesLocally_legacyFile_migratesToEnvelopeIdempotently() {
        let service = makeService()
        let entryId = UUID()
        writeLegacyFormatFile(service: service, entryId: entryId, content: "Migrate me", pin: "4829")

        let first = service.loadAllEntriesLocally(legacyPIN: "4829")
        let second = service.loadAllEntriesLocally(legacyPIN: "4829")

        let a = first.first(where: { $0.id == entryId })
        let b = second.first(where: { $0.id == entryId })
        XCTAssertNotNil(a)
        XCTAssertNotNil(b)
        // Identical results across loads: the second read hits the migrated
        // envelope file, so title/content/dates must not drift.
        XCTAssertEqual(a?.title, b?.title)
        XCTAssertEqual(a?.text, b?.text)
        XCTAssertEqual(a?.createdAt, b?.createdAt)

        // The file is now genuinely envelope-format AND re-encrypted under the
        // data key — so it decrypts WITHOUT a PIN.
        guard let data = LocalJournalStorage.shared.loadEncrypted(entryId: entryId),
              let decrypted = service.encryptionService.decrypt(data) else {
            return XCTFail("migrated file must decrypt under the data key, with no PIN")
        }
        XCTAssertTrue(decrypted.contains("\"content\""), "file should be envelope JSON after migration")
    }

    // MARK: - Local-only entry storage (no accounts, spec 023)

    func test_saveEntryLocally_roundTripsTitleContentAndDates() {
        let service = makeService()
        let entryId = UUID()
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let updated = Date(timeIntervalSince1970: 1_700_000_100)

        let saved = service.saveEntryLocally(
            entryId: entryId, title: "My Entry", content: "Some journal content",
            createdAt: created, updatedAt: updated
        )
        XCTAssertTrue(saved)

        let all = service.loadAllEntriesLocally(legacyPIN: "4829")
        guard let entry = all.first(where: { $0.id == entryId }) else {
            return XCTFail("expected entry \(entryId) to be loadable from local storage")
        }
        XCTAssertEqual(entry.title, "My Entry")
        XCTAssertEqual(entry.text, "Some journal content")
        XCTAssertEqual(entry.createdAt, created)
        XCTAssertEqual(entry.updatedAt, updated)
    }

    // MARK: - Data-key decoupling
    //
    // Content is encrypted under a random Keychain-resident data key, not under
    // PBKDF2(PIN). These pin down the two properties that buys us: entries are
    // readable with no PIN at all, and legacy PIN-encrypted content is migrated
    // on read rather than being orphaned.

    func test_loadAllEntriesLocally_readsEntriesWithNoPINAtAll() {
        let service = makeService()
        let entryId = UUID()
        service.saveEntryLocally(
            entryId: entryId, title: "Secret", content: "Body",
            createdAt: Date(), updatedAt: Date()
        )

        // nil PIN — this used to return nothing and strip the journal bare.
        let all = service.loadAllEntriesLocally(legacyPIN: nil)
        XCTAssertTrue(all.contains { $0.id == entryId },
                      "entries must load without a PIN; the data key is the only thing that matters")
        XCTAssertEqual(all.first(where: { $0.id == entryId })?.text, "Body")
    }

    func test_loadAllEntriesLocally_wrongDataKey_omitsUndecryptableEntries() {
        let service = makeService()
        let entryId = UUID()
        service.saveEntryLocally(
            entryId: entryId, title: "Secret", content: "Body",
            createdAt: Date(), updatedAt: Date()
        )

        // A different Keychain means a different data key — content stays sealed.
        let other = makeService()
        XCTAssertFalse(other.loadAllEntriesLocally(legacyPIN: nil).contains { $0.id == entryId })
    }

    func test_loadAllEntriesLocally_legacyPINEncryptedEnvelope_isRewrittenUnderDataKey() {
        let service = makeService()
        let entryId = UUID()

        // A well-formed envelope sealed under the OLD PBKDF2(PIN) key.
        let envelopeJSON = """
        {"title":"Old Entry","content":"Written before the key change",\
        "createdAt":694224000,"updatedAt":694224000}
        """
        guard let legacy = service.encryptionService.encrypt(envelopeJSON, withPIN: "4829") else {
            return XCTFail("failed to build the legacy fixture")
        }
        try? LocalJournalStorage.shared.saveEncrypted(entryId: entryId, encryptedData: legacy)

        // Without the PIN it is unreadable...
        XCTAssertFalse(service.loadAllEntriesLocally(legacyPIN: nil).contains { $0.id == entryId })

        // ...with it, it is read AND rewritten under the data key.
        let migrated = service.loadAllEntriesLocally(legacyPIN: "4829")
        XCTAssertEqual(migrated.first(where: { $0.id == entryId })?.title, "Old Entry")

        guard let onDisk = LocalJournalStorage.shared.loadEncrypted(entryId: entryId) else {
            return XCTFail("entry file must still exist after migration")
        }
        XCTAssertNotNil(service.encryptionService.decrypt(onDisk),
                        "migration must leave the file readable under the data key")

        // And it now loads with no PIN — the migration is durable, not per-read.
        XCTAssertTrue(service.loadAllEntriesLocally(legacyPIN: nil).contains { $0.id == entryId })
    }

    // MARK: - Cheap cache signature (spec 029): counter fast path + id-set guard

    func test_isEntriesCacheReusable_pureDecision() {
        let a = UUID(), b = UUID()
        let ids: Set<UUID> = [a, b]
        XCTAssertTrue(JournalService.isEntriesCacheReusable(
            cachedCounter: 5, currentCounter: 5, cachedIds: ids, storedIds: ids))
        // Any mutation through the service bumps the counter → not reusable.
        XCTAssertFalse(JournalService.isEntriesCacheReusable(
            cachedCounter: 5, currentCounter: 6, cachedIds: ids, storedIds: ids))
        // A delete that bypassed the service leaves the counter untouched but
        // shrinks the on-disk id set → not reusable.
        XCTAssertFalse(JournalService.isEntriesCacheReusable(
            cachedCounter: 5, currentCounter: 5, cachedIds: ids, storedIds: [a]))
        XCTAssertFalse(JournalService.isEntriesCacheReusable(
            cachedCounter: 5, currentCounter: 5, cachedIds: [a], storedIds: ids))
    }

    func test_shouldRetryFailedEntries_pureDecision() {
        let id = UUID()
        let mtime = Date(timeIntervalSince1970: 100)

        // No failures → nothing to retry, whatever the PIN does.
        XCTAssertFalse(JournalService.shouldRetryFailedEntries(
            failedMtimes: [:], currentMtime: { _ in nil }, failedPIN: nil, currentPIN: "1234"))
        // Same file, same key material → keep the cached (partial) result.
        XCTAssertFalse(JournalService.shouldRetryFailedEntries(
            failedMtimes: [id: mtime], currentMtime: { _ in mtime }, failedPIN: nil, currentPIN: nil))
        // A PIN arriving after unlock is new key material → retry.
        XCTAssertTrue(JournalService.shouldRetryFailedEntries(
            failedMtimes: [id: mtime], currentMtime: { _ in mtime }, failedPIN: nil, currentPIN: "1234"))
        // The failed file was rewritten (migration or out-of-band fix) → retry.
        XCTAssertTrue(JournalService.shouldRetryFailedEntries(
            failedMtimes: [id: mtime], currentMtime: { _ in mtime.addingTimeInterval(5) },
            failedPIN: nil, currentPIN: nil))
        // The failed file vanished entirely → state changed → retry.
        XCTAssertTrue(JournalService.shouldRetryFailedEntries(
            failedMtimes: [id: mtime], currentMtime: { _ in nil }, failedPIN: nil, currentPIN: nil))
    }

    func test_outOfBandDelete_isNotMaskedByTheCounterFastPath() {
        let service = makeService()
        let kept = UUID(), deleted = UUID()
        service.saveEntryLocally(entryId: kept, title: "Kept", content: "A", createdAt: Date(), updatedAt: Date())
        service.saveEntryLocally(entryId: deleted, title: "Doomed", content: "B", createdAt: Date(), updatedAt: Date())
        XCTAssertEqual(service.loadAllEntriesLocally(legacyPIN: nil).filter { $0.id == deleted }.count, 1)

        // The EntryViewModel delete path goes straight to LocalJournalStorage —
        // no counter bump. The id-set guard must still bust the cache.
        LocalJournalStorage.shared.deleteEncrypted(entryId: deleted)

        let after = service.loadAllEntriesLocally(legacyPIN: nil)
        XCTAssertFalse(after.contains { $0.id == deleted })
        XCTAssertTrue(after.contains { $0.id == kept })
    }

    func test_deleteEntryLocally_removesTheEntryAndPurgesItsEmbedding() {
        let service = makeService()
        let id = UUID()
        service.saveEntryLocally(entryId: id, title: "T", content: "B", createdAt: Date(), updatedAt: Date())
        let hash = EmbeddingService.contentHash(title: "T", text: "B")
        EmbeddingService.shared.storeEntryVector([0.1, 0.2, 0.3], id: id, contentHash: hash)

        service.deleteEntryLocally(entryId: id)

        XCTAssertFalse(LocalJournalStorage.shared.hasEncrypted(entryId: id))
        XCTAssertNil(EmbeddingService.shared.cachedEntryVector(id: id, contentHash: hash),
                     "spec 029 R8: the persisted vector must follow its entry")
        XCTAssertFalse(service.loadAllEntriesLocally(legacyPIN: nil).contains { $0.id == id })
    }

    // MARK: - Partial-decrypt tolerance (spec 029)

    func test_partialDecryptFailure_stillServesGoodSubset_andRetriesOnFileChange() {
        let service = makeService()
        let goodId = UUID(), badId = UUID()
        service.saveEntryLocally(entryId: goodId, title: "Good", content: "Readable",
                                 createdAt: Date(), updatedAt: Date())
        // Readable file, undecryptable payload — the "one corrupt file" case
        // that used to force a full re-decrypt on every send.
        let garbage = Data((0..<64).map { _ in UInt8.random(in: 0...255) })
        try? LocalJournalStorage.shared.saveEncrypted(entryId: badId, encryptedData: garbage)

        let first = service.loadAllEntriesLocally(legacyPIN: nil)
        XCTAssertTrue(first.contains { $0.id == goodId }, "the readable subset must survive a corrupt sibling")
        XCTAssertFalse(first.contains { $0.id == badId })

        // Unchanged disk, unchanged key material → stable answer (served from
        // the partial cache; the corrupt file is not hammered every call).
        XCTAssertEqual(Set(service.loadAllEntriesLocally(legacyPIN: nil).map(\.id)),
                       Set(first.map(\.id)))

        // Repair the bad file OUT OF BAND (no service mutation, so no counter
        // bump): a valid envelope under the data key. JSONEncoder's default
        // date strategy is secondsSinceReferenceDate, hence the plain numbers.
        let envelopeJSON = #"{"title":"Fixed","content":"Now readable","createdAt":0,"updatedAt":0,"hasPhoto":false}"#
        guard let fixed = service.encryptionService.encrypt(envelopeJSON) else {
            return XCTFail("failed to build the repaired fixture")
        }
        try? LocalJournalStorage.shared.saveEncrypted(entryId: badId, encryptedData: fixed)
        // Force an unambiguous mtime change — the failed-id mtime trigger is
        // exactly what must cause the retry.
        let fileURL = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EncryptedJournals/\(badId.uuidString).encrypted")
        try? FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(10)], ofItemAtPath: fileURL.path)

        let repaired = service.loadAllEntriesLocally(legacyPIN: nil)
        XCTAssertEqual(repaired.first { $0.id == badId }?.title, "Fixed",
                       "a failed id must be retried once its file changes")
        XCTAssertTrue(repaired.contains { $0.id == goodId })
    }

    // MARK: - Cold-load dedupe (spec 029 Amendment A, audit F7)

    func test_concurrentColdLoads_payForExactlyOneFullDecrypt() {
        let service = makeService()
        let ids = (0..<3).map { _ in UUID() }
        for (i, id) in ids.enumerated() {
            service.saveEntryLocally(entryId: id, title: "T\(i)", content: "Body \(i)",
                                     createdAt: Date(), updatedAt: Date())
        }
        XCTAssertEqual(service.fullLoadCount, 0, "no load has run yet")

        // Cold cache, many simultaneous callers — the launch-time shape:
        // the prewarm chain's detached task and the journal view's appear
        // load racing. Every caller must get the full result, but only ONE
        // may pay the corpus decrypt; the rest block on the in-flight load
        // and reuse the cache it arms.
        let resultsLock = NSLock()
        var results: [[Entry]] = []
        DispatchQueue.concurrentPerform(iterations: 8) { _ in
            let loaded = service.loadAllEntriesLocally(legacyPIN: nil)
            resultsLock.lock(); results.append(loaded); resultsLock.unlock()
        }

        XCTAssertEqual(results.count, 8)

        for result in results {
            XCTAssertEqual(Set(result.map(\.id)), Set(ids), "every concurrent caller sees the full corpus")
        }
        XCTAssertEqual(service.fullLoadCount, 1,
                       "concurrent cold callers must dedupe onto a single decrypt pass")
    }

    // MARK: - Corpus generation (spec 029 Amendment A, audit F8)

    func test_currentEntriesGeneration_bumpsOnEveryContentMutation() {
        let service = makeService()
        let g0 = service.currentEntriesGeneration()
        XCTAssertEqual(service.currentEntriesGeneration(), g0, "reading the generation must not change it")

        let id = UUID()
        service.saveEntryLocally(entryId: id, title: "T", content: "B", createdAt: Date(), updatedAt: Date())
        let g1 = service.currentEntriesGeneration()
        XCTAssertGreaterThan(g1, g0, "a save is a content mutation")

        // A pure read leaves the generation alone — that is the property the
        // per-entry hash cache keys on ("unchanged generation ⇒ unchanged bytes").
        _ = service.loadAllEntriesLocally(legacyPIN: nil)
        XCTAssertEqual(service.currentEntriesGeneration(), g1)

        service.deleteEntryLocally(entryId: id)
        XCTAssertGreaterThan(service.currentEntriesGeneration(), g1, "a delete through the service bumps too")

        let g2 = service.currentEntriesGeneration()
        service.invalidateEntriesCache()
        XCTAssertGreaterThan(service.currentEntriesGeneration(), g2, "invalidation counts as a generation change")
    }

    // MARK: - EntryViewModel load-if-needed guard (spec 029 Amendment A, audit F7)

    @MainActor
    func test_loadEntriesIfNeeded_skipsWhenAlreadyLoaded() async {
        let vm = EntryViewModel()
        // Simulate a completed first load holding state a real reload would
        // clobber (the real storage behind JournalService.shared is empty or
        // undecryptable here, so an accidental reload empties `entries`).
        vm.hasInitiallyLoaded = true
        vm.entries = [Entry(id: UUID(), title: "Loaded", text: "Kept",
                            createdAt: Date(), updatedAt: Date())]

        await vm.loadEntriesIfNeeded()

        XCTAssertEqual(vm.entries.count, 1, "loadEntriesIfNeeded must be a no-op once loaded")
        XCTAssertEqual(vm.entries.first?.title, "Loaded")
        XCTAssertFalse(vm.isLoading)
    }

    func test_saveEntryLocally_overwritesPreviousVersionOnSameId() {
        let service = makeService()
        let entryId = UUID()
        let t1 = Date(timeIntervalSince1970: 1_700_000_000)
        let t2 = Date(timeIntervalSince1970: 1_700_000_500)

        service.saveEntryLocally(entryId: entryId, title: "First", content: "v1", createdAt: t1, updatedAt: t1)
        service.saveEntryLocally(entryId: entryId, title: "First", content: "v2 edited", createdAt: t1, updatedAt: t2)

        let all = service.loadAllEntriesLocally(legacyPIN: "4829")
        let matching = all.filter { $0.id == entryId }
        XCTAssertEqual(matching.count, 1, "an edit must overwrite, not duplicate, the local entry")
        XCTAssertEqual(matching.first?.text, "v2 edited")
        XCTAssertEqual(matching.first?.updatedAt, t2)
    }

}
