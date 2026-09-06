import XCTest
@testable import MeetMemento

/// Spec 029 latency floor: no-RAG turns must not wait on the journal loader;
/// notebook still loads before retrieve.
final class AskLatencyFloorTests: XCTestCase {

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        var isSet: Bool {
            lock.lock(); defer { lock.unlock() }
            return value
        }
        func set() {
            lock.lock(); value = true; lock.unlock()
        }
    }

    func test_companion_doesNotAwaitJournalLoader() async {
        let hanging = expectation(description: "loader must not run")
        hanging.isInverted = true
        let entries = await FoundationModelsIntelligenceService.resolveJournalEntries(
            channel: .companion,
            provided: Entry.sampleEntries,
            loadEntries: {
                hanging.fulfill()
                try? await Task.sleep(for: .seconds(30))
                return Entry.sampleEntries
            }
        )
        XCTAssertTrue(entries.isEmpty)
        await fulfillment(of: [hanging], timeout: 0.2)
    }

    func test_phatic_doesNotAwaitJournalLoader() async {
        let called = Flag()
        let entries = await FoundationModelsIntelligenceService.resolveJournalEntries(
            channel: .phatic,
            provided: Entry.sampleEntries,
            loadEntries: {
                called.set()
                return Entry.sampleEntries
            }
        )
        XCTAssertFalse(called.isSet)
        XCTAssertTrue(entries.isEmpty)
    }

    func test_notebook_awaitsLoaderBeforeRetrieve() async {
        let called = Flag()
        let loaded = await FoundationModelsIntelligenceService.resolveJournalEntries(
            channel: .notebook,
            provided: [],
            loadEntries: {
                called.set()
                return Entry.sampleEntries
            }
        )
        XCTAssertTrue(called.isSet)
        XCTAssertEqual(loaded.count, Entry.sampleEntries.count)
        XCTAssertTrue(ReplyChannel.notebook.allowsRetrieval)
        let retrieval = EntryRetriever.retrieve(
            RetrievalQuery(currentMessage: "What have I been writing about lately?"),
            entries: loaded
        )
        XCTAssertFalse(retrieval.isEmpty, "notebook evidence must exist before generation")
    }

    func test_typedNotebook_usesProvidedEntriesWhenNoLoader() async {
        let loaded = await FoundationModelsIntelligenceService.resolveJournalEntries(
            channel: .notebook,
            provided: Entry.sampleEntries,
            loadEntries: nil
        )
        XCTAssertEqual(loaded.count, Entry.sampleEntries.count)
    }

    func test_statistic_doesNotUseJournalLoaderSeam() async {
        let called = Flag()
        let entries = await FoundationModelsIntelligenceService.resolveJournalEntries(
            channel: .statistic,
            provided: Entry.sampleEntries,
            loadEntries: {
                called.set()
                return Entry.sampleEntries
            }
        )
        XCTAssertFalse(called.isSet)
        XCTAssertTrue(entries.isEmpty)
        XCTAssertFalse(ReplyChannel.statistic.allowsRetrieval)
    }

    func test_thread_awaitsLoader() async {
        let called = Flag()
        _ = await FoundationModelsIntelligenceService.resolveJournalEntries(
            channel: .thread,
            provided: [],
            loadEntries: {
                called.set()
                return Entry.sampleEntries
            }
        )
        XCTAssertTrue(called.isSet)
    }
}
