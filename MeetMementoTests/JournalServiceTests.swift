import XCTest
@testable import MeetMemento

/// Coverage note: the journal is on-device only, so there is no
/// CRUD-over-network path to test. What's covered here is local persistence,
/// legacy-format migration, and the data-key decoupling from the session PIN.
final class JournalServiceTests: XCTestCase {
    private func makeService() -> JournalService {
        JournalService(encryptionService: EncryptionService(keychain: InMemoryKeychainStore()))
    }

    override func tearDown() {
        for id in LocalJournalStorage.shared.allStoredEntryIds() {
            LocalJournalStorage.shared.deleteEncrypted(entryId: id)
        }
        super.tearDown()
    }

    // MARK: - Legacy-format migration (pre-local-only builds)

    private func writeLegacyFormatFile(service: JournalService, entryId: UUID, content: String, pin: String) {
        guard let encrypted = service.encryptionService.encrypt(content, withPIN: pin) else {
            return XCTFail("failed to encrypt legacy fixture")
        }
        try? LocalJournalStorage.shared.saveEncrypted(entryId: entryId, encryptedData: encrypted)
    }

    func test_loadAllEntriesLocally_legacyFile_recoversTitleFromLegacyPendingSyncRecord() {
        let service = makeService()
        let entryId = UUID()
        writeLegacyFormatFile(service: service, entryId: entryId, content: "Body of an old entry", pin: "4829")

        guard let encryptedTitle = service.encryptionService.encrypt("Recovered Title") else {
            return XCTFail("failed to encrypt legacy title fixture")
        }
        let record = LegacyPendingSyncFixture(encryptedTitle: encryptedTitle)
        let pendingURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PendingSync", isDirectory: true)
        try? FileManager.default.createDirectory(at: pendingURL, withIntermediateDirectories: true)
        let fileURL = pendingURL.appendingPathComponent("\(entryId.uuidString).json")
        try? JSONEncoder().encode(record).write(to: fileURL)

        let all = service.loadAllEntriesLocally(legacyPIN: "4829")
        guard let entry = all.first(where: { $0.id == entryId }) else {
            return XCTFail("legacy entry must not be dropped")
        }
        XCTAssertEqual(entry.title, "Recovered Title")
        XCTAssertEqual(entry.text, "Body of an old entry")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
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
        XCTAssertEqual(a?.title, b?.title)
        XCTAssertEqual(a?.text, b?.text)
        XCTAssertEqual(a?.createdAt, b?.createdAt)

        guard let data = LocalJournalStorage.shared.loadEncrypted(entryId: entryId),
              let decrypted = service.encryptionService.decrypt(data) else {
            return XCTFail("migrated file must decrypt under the data key, with no PIN")
        }
        XCTAssertTrue(decrypted.contains("\"content\""), "file should be envelope JSON after migration")
    }

    // MARK: - Local-only entry storage

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

    func test_loadAllEntriesLocally_readsEntriesWithNoPINAtAll() {
        let service = makeService()
        let entryId = UUID()
        service.saveEntryLocally(
            entryId: entryId, title: "Secret", content: "Body",
            createdAt: Date(), updatedAt: Date()
        )

        let all = service.loadAllEntriesLocally(legacyPIN: nil)
        XCTAssertTrue(all.contains { $0.id == entryId })
        XCTAssertEqual(all.first(where: { $0.id == entryId })?.text, "Body")
    }

    func test_loadAllEntriesLocally_wrongDataKey_omitsUndecryptableEntries() {
        let service = makeService()
        let entryId = UUID()
        service.saveEntryLocally(
            entryId: entryId, title: "Secret", content: "Body",
            createdAt: Date(), updatedAt: Date()
        )

        let other = makeService()
        XCTAssertFalse(other.loadAllEntriesLocally(legacyPIN: nil).contains { $0.id == entryId })
    }

    func test_loadAllEntriesLocally_legacyPINEncryptedEnvelope_isRewrittenUnderDataKey() {
        let service = makeService()
        let entryId = UUID()

        let envelopeJSON = """
        {"title":"Old Entry","content":"Written before the key change",\
        "createdAt":694224000,"updatedAt":694224000}
        """
        guard let legacy = service.encryptionService.encrypt(envelopeJSON, withPIN: "4829") else {
            return XCTFail("failed to build the legacy fixture")
        }
        try? LocalJournalStorage.shared.saveEncrypted(entryId: entryId, encryptedData: legacy)

        XCTAssertFalse(service.loadAllEntriesLocally(legacyPIN: nil).contains { $0.id == entryId })

        let migrated = service.loadAllEntriesLocally(legacyPIN: "4829")
        XCTAssertEqual(migrated.first(where: { $0.id == entryId })?.title, "Old Entry")

        guard let onDisk = LocalJournalStorage.shared.loadEncrypted(entryId: entryId) else {
            return XCTFail("entry file must still exist after migration")
        }
        XCTAssertNotNil(service.encryptionService.decrypt(onDisk))

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
        XCTAssertEqual(matching.count, 1)
        XCTAssertEqual(matching.first?.text, "v2 edited")
        XCTAssertEqual(matching.first?.updatedAt, t2)
    }
}

private struct LegacyPendingSyncFixture: Codable {
    let encryptedTitle: Data
}
