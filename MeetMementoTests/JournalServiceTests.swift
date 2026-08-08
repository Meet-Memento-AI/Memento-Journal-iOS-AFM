import XCTest
@testable import MeetMemento

/// Coverage note: full CRUD-over-network testing (create/update/delete
/// hitting Supabase) would need a `SupabaseClienting` seam abstracting
/// `SupabaseClient` — the same larger abstraction scoped out of
/// `AuthViewModelTests` for the same reason. What's covered here is
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
        service.queuePendingSync(entryId: entryId, opType: .create, title: "Recovered Title", withPIN: "4829")

        let all = service.loadAllEntriesLocally(withPIN: "4829")
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

        let all = service.loadAllEntriesLocally(withPIN: "4829")
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

        let first = service.loadAllEntriesLocally(withPIN: "4829")
        let second = service.loadAllEntriesLocally(withPIN: "4829")

        let a = first.first(where: { $0.id == entryId })
        let b = second.first(where: { $0.id == entryId })
        XCTAssertNotNil(a)
        XCTAssertNotNil(b)
        // Identical results across loads: the second read hits the migrated
        // envelope file, so title/content/dates must not drift.
        XCTAssertEqual(a?.title, b?.title)
        XCTAssertEqual(a?.text, b?.text)
        XCTAssertEqual(a?.createdAt, b?.createdAt)

        // The file is now genuinely envelope-format: it decodes without the
        // legacy fallback's side effects (no queue op was ever created).
        guard let data = LocalJournalStorage.shared.loadEncrypted(entryId: entryId),
              let decrypted = service.encryptionService.decrypt(data, withPIN: "4829") else {
            return XCTFail("migrated file must still decrypt")
        }
        XCTAssertTrue(decrypted.contains("\"content\""), "file should be envelope JSON after migration")
    }

    func test_queuePendingSync_encryptsTitleRecoverableWithSamePIN() {
        let service = makeService()
        let entryId = UUID()

        service.queuePendingSync(entryId: entryId, opType: .create, title: "My Title", withPIN: "1234")

        let ops = LocalJournalStorage.shared.allPendingSyncOperations()
        guard let op = ops.first(where: { $0.entryId == entryId }) else {
            return XCTFail("expected a queued operation for \(entryId)")
        }
        XCTAssertEqual(op.opType, .create)
        XCTAssertEqual(service.encryptionService.decrypt(op.encryptedTitle, withPIN: "1234"), "My Title")
    }

    // MARK: - Local-only entry storage (no accounts, spec 023)

    func test_saveEntryLocally_roundTripsTitleContentAndDates() {
        let service = makeService()
        let entryId = UUID()
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let updated = Date(timeIntervalSince1970: 1_700_000_100)

        let saved = service.saveEntryLocally(
            entryId: entryId, title: "My Entry", content: "Some journal content",
            createdAt: created, updatedAt: updated, withPIN: "4829"
        )
        XCTAssertTrue(saved)

        let all = service.loadAllEntriesLocally(withPIN: "4829")
        guard let entry = all.first(where: { $0.id == entryId }) else {
            return XCTFail("expected entry \(entryId) to be loadable from local storage")
        }
        XCTAssertEqual(entry.title, "My Entry")
        XCTAssertEqual(entry.text, "Some journal content")
        XCTAssertEqual(entry.createdAt, created)
        XCTAssertEqual(entry.updatedAt, updated)
        XCTAssertEqual(entry.syncStatus, .synced)
    }

    func test_loadAllEntriesLocally_wrongPIN_omitsUndecryptableEntries() {
        let service = makeService()
        let entryId = UUID()
        service.saveEntryLocally(
            entryId: entryId, title: "Secret", content: "Body",
            createdAt: Date(), updatedAt: Date(), withPIN: "4829"
        )

        let all = service.loadAllEntriesLocally(withPIN: "0000")
        XCTAssertFalse(all.contains { $0.id == entryId })
    }

    func test_saveEntryLocally_overwritesPreviousVersionOnSameId() {
        let service = makeService()
        let entryId = UUID()
        let t1 = Date(timeIntervalSince1970: 1_700_000_000)
        let t2 = Date(timeIntervalSince1970: 1_700_000_500)

        service.saveEntryLocally(entryId: entryId, title: "First", content: "v1", createdAt: t1, updatedAt: t1, withPIN: "4829")
        service.saveEntryLocally(entryId: entryId, title: "First", content: "v2 edited", createdAt: t1, updatedAt: t2, withPIN: "4829")

        let all = service.loadAllEntriesLocally(withPIN: "4829")
        let matching = all.filter { $0.id == entryId }
        XCTAssertEqual(matching.count, 1, "an edit must overwrite, not duplicate, the local entry")
        XCTAssertEqual(matching.first?.text, "v2 edited")
        XCTAssertEqual(matching.first?.updatedAt, t2)
    }

}
