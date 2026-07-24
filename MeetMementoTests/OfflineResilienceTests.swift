import XCTest
@testable import MeetMemento

final class PendingSyncQueueTests: XCTestCase {
    override func tearDown() {
        LocalJournalStorage.shared.clearAll()
        for op in LocalJournalStorage.shared.allPendingSyncOperations() {
            LocalJournalStorage.shared.dequeuePendingSync(entryId: op.entryId)
        }
        super.tearDown()
    }

    func test_PendingSyncOperation_encodesAndDecodesRoundTrip() throws {
        let op = PendingSyncOperation(
            entryId: UUID(),
            opType: .create,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            encryptedTitle: Data([0x01, 0x02, 0x03, 0xFF])
        )

        let data = try JSONEncoder().encode(op)
        let decoded = try JSONDecoder().decode(PendingSyncOperation.self, from: data)

        XCTAssertEqual(decoded.entryId, op.entryId)
        XCTAssertEqual(decoded.opType, op.opType)
        XCTAssertEqual(decoded.timestamp, op.timestamp)
        XCTAssertEqual(decoded.encryptedTitle, op.encryptedTitle)
    }

    func test_enqueueThenDequeue_removesFromQueue() {
        let entryId = UUID()
        let op = PendingSyncOperation(entryId: entryId, opType: .update, timestamp: Date(), encryptedTitle: Data([0xAB]))

        LocalJournalStorage.shared.enqueuePendingSync(op)
        XCTAssertTrue(LocalJournalStorage.shared.hasPendingSync(entryId: entryId))

        LocalJournalStorage.shared.dequeuePendingSync(entryId: entryId)
        XCTAssertFalse(LocalJournalStorage.shared.hasPendingSync(entryId: entryId))
    }

    func test_enqueueForSameEntryTwice_replacesRatherThanStacks() {
        let entryId = UUID()
        LocalJournalStorage.shared.enqueuePendingSync(
            PendingSyncOperation(entryId: entryId, opType: .create, timestamp: Date(), encryptedTitle: Data([0x01]))
        )
        LocalJournalStorage.shared.enqueuePendingSync(
            PendingSyncOperation(entryId: entryId, opType: .update, timestamp: Date(), encryptedTitle: Data([0x02]))
        )

        let matching = LocalJournalStorage.shared.allPendingSyncOperations().filter { $0.entryId == entryId }
        XCTAssertEqual(matching.count, 1)
        XCTAssertEqual(matching.first?.opType, .update)

        LocalJournalStorage.shared.dequeuePendingSync(entryId: entryId)
    }

    func test_allPendingSyncOperations_ordersOldestFirst() {
        let older = PendingSyncOperation(entryId: UUID(), opType: .create, timestamp: Date(timeIntervalSince1970: 100), encryptedTitle: Data())
        let newer = PendingSyncOperation(entryId: UUID(), opType: .create, timestamp: Date(timeIntervalSince1970: 200), encryptedTitle: Data())

        // Enqueue newer first to confirm ordering isn't just insertion order.
        LocalJournalStorage.shared.enqueuePendingSync(newer)
        LocalJournalStorage.shared.enqueuePendingSync(older)

        let ops = LocalJournalStorage.shared.allPendingSyncOperations()
        let index = { (id: UUID) in ops.firstIndex(where: { $0.entryId == id }) }
        XCTAssertLessThan(index(older.entryId) ?? -1, index(newer.entryId) ?? -1)

        LocalJournalStorage.shared.dequeuePendingSync(entryId: older.entryId)
        LocalJournalStorage.shared.dequeuePendingSync(entryId: newer.entryId)
    }
}

// MARK: - NetworkMonitoring mock

/// Simple settable mock so any code depending on `NetworkMonitoring` (rather
/// than the concrete `NetworkMonitor`) can be driven in tests without a real
/// `NWPathMonitor`.
@MainActor
final class MockNetworkMonitor: NetworkMonitoring {
    var isConnected: Bool

    init(isConnected: Bool = true) {
        self.isConnected = isConnected
    }
}

@MainActor
final class NetworkMonitoringProtocolTests: XCTestCase {
    func test_mockNetworkMonitor_reflectsAssignedState() {
        let mock = MockNetworkMonitor(isConnected: true)
        let seam: NetworkMonitoring = mock
        XCTAssertTrue(seam.isConnected)

        mock.isConnected = false
        XCTAssertFalse(seam.isConnected)
    }
}
