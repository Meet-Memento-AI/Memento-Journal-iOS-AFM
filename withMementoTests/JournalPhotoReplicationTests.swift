import SwiftData
import UIKit
import XCTest
@testable import withMemento

final class JournalPhotoReplicationTests: XCTestCase {
    private var container: ModelContainer!
    private var encryption: EncryptionService!

    override func setUp() {
        super.setUp()
        container = JournalContainer.makeInMemory()
        JournalContainer.resetCacheForTests(to: container)
        encryption = EncryptionService(keychain: InMemoryKeychainStore())
        JournalPhotoReplication.clearMigrationFlagForTests()
        PhotoStorage.shared.clearAll()
    }

    override func tearDown() {
        JournalPhotoReplication.clearMigrationFlagForTests()
        PhotoStorage.shared.clearAll()
        JournalContainer.resetCacheForTests(to: nil)
        container = nil
        super.tearDown()
    }

    func test_persistMirroredCover_roundTripsAcrossNewContext() {
        let entryId = UUID()
        let jpeg = makeJPEG()
        seedEntry(id: entryId, hasPhoto: true)

        JournalPhotoReplication.persistMirroredCover(jpeg: jpeg, entryId: entryId, container: container)

        XCTAssertEqual(JournalPhotoReplication.mirroredCoverJPEG(entryId: entryId, container: container), jpeg)
        let otherContext = ModelContext(container)
        var descriptor = FetchDescriptor<StoredEntry>(predicate: #Predicate { $0.id == entryId })
        descriptor.fetchLimit = 1
        let row = try? otherContext.fetch(descriptor).first
        XCTAssertEqual(row?.attachments?.first?.coverJPEGData, jpeg)
    }

    func test_migrateLocalEncryptedPhotos_uploadsCoverAsset() {
        let entryId = UUID()
        seedEntry(id: entryId, hasPhoto: true)
        let jpeg = makeJPEG()
        guard let encrypted = encryption.encryptData(jpeg) else {
            return XCTFail("fixture encrypt failed")
        }
        try? PhotoStorage.shared.saveEncrypted(entryId: entryId, encryptedData: encrypted)

        JournalPhotoReplication.migrateLocalEncryptedPhotosIfNeeded(
            encryption: encryption,
            container: container
        )

        XCTAssertEqual(
            JournalPhotoReplication.mirroredCoverJPEG(entryId: entryId, container: container),
            jpeg
        )
        XCTAssertTrue(JournalPhotoReplication.hasCompletedBulkMigration)
    }

    func test_loadCoverJPEGBytes_fallsBackToMirroredAsset() {
        let entryId = UUID()
        seedEntry(id: entryId, hasPhoto: true)
        let jpeg = makeJPEG()
        JournalPhotoReplication.persistMirroredCover(jpeg: jpeg, entryId: entryId, container: container)

        let loaded = JournalPhotoReplication.loadCoverJPEGBytes(
            entryId: entryId,
            encryption: encryption,
            container: container
        )
        XCTAssertEqual(loaded, jpeg)
    }

    func test_reconcileMissingCover_clearsPhantomPhotoMetadata() {
        let entryId = UUID()
        seedEntry(id: entryId, hasPhoto: true)
        XCTAssertTrue(JournalPhotoReplication.reconcileMissingCover(entryId: entryId, container: container))
        XCTAssertFalse(MementoDataStore.entry(id: entryId, container: container)?.hasPhoto ?? true)
    }

    func test_reconcileMissingCover_keepsEntryWhenMirroredBytesExist() {
        let entryId = UUID()
        seedEntry(id: entryId, hasPhoto: true)
        JournalPhotoReplication.persistMirroredCover(
            jpeg: makeJPEG(),
            entryId: entryId,
            container: container
        )
        XCTAssertFalse(JournalPhotoReplication.reconcileMissingCover(entryId: entryId, container: container))
        XCTAssertTrue(MementoDataStore.entry(id: entryId, container: container)?.hasPhoto ?? false)
    }

    private func seedEntry(id: UUID, hasPhoto: Bool) {
        MementoDataStore.upsertEntry(
            id: id,
            title: "T",
            transcript: "B",
            createdAt: Date(),
            updatedAt: Date(),
            hasPhoto: hasPhoto,
            container: container
        )
    }

    private func makeJPEG() -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            XCTFail("jpeg encode failed")
            return Data()
        }
        return data
    }
}
