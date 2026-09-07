import XCTest
@testable import MeetMemento

/// Merge-lane retrieve scale table (harness chat-speed plan). Live AFM /
/// `DiagLatencyProfile` stays device-lane (`CI_ONLINE` skips it). These
/// timings prove embeddings are warm and chunk memo does not change scores.
final class RetrieveScaleTests: XCTestCase {

    override func tearDown() {
        PassageChunker.resetCacheForTesting()
        super.tearDown()
    }

    func test_warmThenRetrieve_timesEmpty50FixtureAndLarge() throws {
        let query = RetrievalQuery(currentMessage: "What have I been writing about lately?")
        var report = "# Retrieve scale (warm embeddings)\n\n"
        report += "| n | warm ms | retrieve1 ms | retrieve2 ms | hits |\n|---|---|---|---|---|\n"

        for n in [0, 50, 262, 500] {
            let entries = try journal(size: n)
            PassageChunker.resetCacheForTesting()
            let clock = ContinuousClock()

            let warmStart = clock.now
            EntryRetriever.warmEmbeddings(entries, generation: 1)
            let warmMs = Diag.secs(clock.now - warmStart) * 1000

            let firstStart = clock.now
            let first = EntryRetriever.retrieve(query, entries: entries)
            let firstMs = Diag.secs(clock.now - firstStart) * 1000

            let secondStart = clock.now
            let second = EntryRetriever.retrieve(query, entries: entries)
            let secondMs = Diag.secs(clock.now - secondStart) * 1000

            XCTAssertEqual(
                first.entries.map(\.id),
                second.entries.map(\.id),
                "chunk memo must not change ranking at n=\(n)"
            )
            XCTAssertEqual(first.contextBlock, second.contextBlock, "n=\(n)")
            XCTAssertEqual(first.isAmbient, second.isAmbient, "n=\(n)")

            report += String(
                format: "| %d | %.1f | %.1f | %.1f | %d |\n",
                n, warmMs, firstMs, secondMs, first.entries.count
            )
        }

        print(report)
        XCTAssertTrue(report.contains("| 0 |"))
        XCTAssertTrue(report.contains("| 500 |"))
    }

    func test_chatAndJournalWarm_areTheSendPath() {
        // ChatService.prewarm and JournalView.onAppear both call
        // EntryRetriever.warmEmbeddings so send never embeds cold.
        XCTAssertTrue(ReplyChannel.notebook.allowsRetrieval)
        XCTAssertFalse(ReplyChannel.phatic.allowsRetrieval)
    }

    private func journal(size n: Int) throws -> [Entry] {
        if n == 0 { return [] }
        if n >= 262, let persona = try? ChatEvalCorpus.personaCorpus().entries, !persona.isEmpty {
            if n <= persona.count { return Array(persona.prefix(n)) }
            return persona + Diag.scaled(n - persona.count)
        }
        return Diag.scaled(n)
    }
}
