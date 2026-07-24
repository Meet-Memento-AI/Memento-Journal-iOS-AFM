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

    // MARK: - Local-first helpers

    func test_saveEncryptedLocally_roundTripsThroughSameServiceInstance() {
        let service = makeService()
        let entryId = UUID()

        let saved = service.saveEncryptedLocally(entryId: entryId, content: "local-first content", withPIN: "1234")
        XCTAssertTrue(saved)

        guard let data = LocalJournalStorage.shared.loadEncrypted(entryId: entryId) else {
            return XCTFail("expected encrypted content to be saved locally")
        }
        // Same EncryptionService instance (same mock keychain/salt) can decrypt what it wrote.
        XCTAssertEqual(service.encryptionService.decrypt(data, withPIN: "1234"), "local-first content")
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

    // MARK: - Retry/error classification

    func test_isTransientError_trueForRetryableURLErrors() {
        let service = makeService()
        for code in [NSURLErrorTimedOut, NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorCannotConnectToHost] {
            let error = NSError(domain: NSURLErrorDomain, code: code)
            XCTAssertTrue(service.isTransientError(error), "expected code \(code) to be transient")
        }
    }

    func test_isTransientError_trueForServerAndRateLimitHTTPStatus() {
        let service = makeService()
        XCTAssertTrue(service.isTransientError(URLError(.init(rawValue: 500))))
        XCTAssertTrue(service.isTransientError(URLError(.init(rawValue: 429))))
    }

    func test_isTransientError_falseForClientErrorsAndUnrelatedErrors() {
        let service = makeService()
        XCTAssertFalse(service.isTransientError(URLError(.init(rawValue: 404))))
        XCTAssertFalse(service.isTransientError(NSError(domain: "SomethingElse", code: 1)))
    }
}
