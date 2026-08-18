import XCTest
@testable import MeetMemento

final class LocalJournalStorageWipeTests: XCTestCase {
    override func tearDown() {
        LocalJournalStorage.shared.clearAll()
        super.tearDown()
    }

    /// Pre-1.x installs may still have a `Documents/PendingSync` folder.
    /// Delete-everything and first storage access must remove it so the
    /// binary never looks like it still has a server queue.
    func test_clearAll_removesLegacyPendingSyncDirectory() throws {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let leftover = documents.appendingPathComponent("PendingSync", isDirectory: true)
        try FileManager.default.createDirectory(at: leftover, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: leftover.appendingPathComponent("dummy.json"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: leftover.path))

        LocalJournalStorage.shared.clearAll()

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: leftover.path),
            "delete-everything must remove leftover PendingSync"
        )
    }

    func test_purgeLegacyPendingSyncDirectory_isIdempotentWhenMissing() {
        LocalJournalStorage.shared.purgeLegacyPendingSyncDirectory()
        LocalJournalStorage.shared.purgeLegacyPendingSyncDirectory()
    }
}
