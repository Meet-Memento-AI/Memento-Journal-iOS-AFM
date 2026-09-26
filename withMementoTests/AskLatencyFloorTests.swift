import XCTest
@testable import withMemento

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

    // MARK: - Stall watchdog (spec 029 R7)

    /// Narration is half-duplex: the mic is down for the whole of "Thinking…",
    /// so a spoken turn must give up long before the typed chat page does.
    func test_watchdogTimeout_spokenFailsFasterThanTyped() {
        let typed = FoundationModelsIntelligenceService.generationWatchdogTimeout(spoken: false)
        let spoken = FoundationModelsIntelligenceService.generationWatchdogTimeout(spoken: true)
        XCTAssertEqual(typed, .seconds(30))
        XCTAssertEqual(spoken, .seconds(8))
        XCTAssertLessThan(spoken, typed)
    }

    /// A fixed 5s poll against an 8s deadline fires anywhere in 10–15s, giving
    /// back most of what the shorter deadline buys. The tick tracks the
    /// deadline instead, so worst-case overshoot stays proportional.
    func test_watchdogPollInterval_tracksDeadline() {
        let typedTick = FoundationModelsIntelligenceService.watchdogPollInterval(
            for: .seconds(30)
        )
        let spokenTick = FoundationModelsIntelligenceService.watchdogPollInterval(
            for: .seconds(8)
        )
        XCTAssertEqual(typedTick, .milliseconds(3_750))
        XCTAssertEqual(spokenTick, .seconds(1))

        // Worst-case fire time is deadline + one tick. Spoken must still land
        // inside the window where re-arming the mic reads as responsive.
        XCTAssertLessThanOrEqual(Duration.seconds(8) + spokenTick, .seconds(10))

        // Clamped at both ends: never busier than 250ms, never lazier than 5s.
        XCTAssertEqual(
            FoundationModelsIntelligenceService.watchdogPollInterval(for: .seconds(1)),
            .milliseconds(250)
        )
        XCTAssertEqual(
            FoundationModelsIntelligenceService.watchdogPollInterval(for: .seconds(120)),
            .seconds(5)
        )
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
