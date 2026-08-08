import XCTest
@testable import MeetMemento

/// Coverage note: the journal is on-device only, so there is no
/// CRUD-over-network path to test. What's covered here is
/// everything reachable without that seam: the local-first helpers added
/// in this session's offline-resilience work (via an injected
/// `EncryptionService` so no test touches the real Keychain), the pending
/// sync queue's encrypted-title round trip, and the retry/error
/// classification logic `withRetry` depends on.
final class JournalServiceTests: XCTestCase {
    private func makeService() -> JournalService {
        JournalService(encryptionService: EncryptionService(keychain: InMemoryKeychainStore()))
    }

    override func tearDown() {
        for id in LocalJournalStorage.shared.allStoredEntryIds() {
            LocalJournalStorage.shared.deleteEncrypted(entryId: id)
        }
        for op in LocalJournalStorage.shared.allPendingSyncOperations() {
            LocalJournalStorage.shared.dequeuePendingSync(entryId: op.entryId)
        }
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

    func test_loadAllEntriesLocally_legacyFile_recoversTitleFromPendingSyncQueue() {
        let service = makeService()
        let entryId = UUID()
        writeLegacyFormatFile(service: service, entryId: entryId, content: "Body of an old entry", pin: "4829")
        // Entries created since the account removal all queued a pending-sync
        // op (their network call always failed) — its encryptedTitle is the
        // only local record of the title.
        service.queuePendingSync(entryId: entryId, opType: .create, title: "Recovered Title")

        let all = service.loadAllEntriesLocally(legacyPIN: "4829")
        guard let entry = all.first(where: { $0.id == entryId }) else {
            return XCTFail("legacy entry must not be dropped")
        }
        XCTAssertEqual(entry.title, "Recovered Title")
        XCTAssertEqual(entry.text, "Body of an old entry")
        // Migration cleans up the queue file.
        XCTAssertFalse(LocalJournalStorage.shared.hasPendingSync(entryId: entryId))
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

    func test_queuePendingSync_encryptsTitleUnderDataKey() {
        let service = makeService()
        let entryId = UUID()

        service.queuePendingSync(entryId: entryId, opType: .create, title: "My Title")

        let ops = LocalJournalStorage.shared.allPendingSyncOperations()
        guard let op = ops.first(where: { $0.entryId == entryId }) else {
            return XCTFail("expected a queued operation for \(entryId)")
        }
        XCTAssertEqual(op.opType, .create)
        XCTAssertEqual(service.encryptionService.decrypt(op.encryptedTitle), "My Title")
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
        XCTAssertEqual(entry.syncStatus, .synced)
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
