import XCTest
@testable import MeetMemento

final class RunningTranscriptTests: XCTestCase {

    func test_volatileThenFinalThenVolatile_concatenates() {
        var running = RunningTranscript()
        running.apply(.volatile("Hello there"))
        XCTAssertEqual(running.display, "Hello there")

        running.apply(.finalized("Hello there."))
        XCTAssertEqual(running.committed, "Hello there.")
        XCTAssertEqual(running.display, "Hello there.",
                       "a segment final must not flash the utterance empty")

        running.apply(.volatile("I wanted to talk about my week"))
        XCTAssertEqual(
            running.display,
            "Hello there. I wanted to talk about my week",
            "the next volatile is a tail, not a replacement"
        )
    }

    func test_cumulativeVolatile_doesNotDouble() {
        var running = RunningTranscript()
        running.apply(.finalized("Hello there."))
        running.apply(.volatile("Hello there. I wanted to talk"))
        XCTAssertEqual(
            running.display,
            "Hello there. I wanted to talk",
            "when the engine restates the whole utterance, do not prepend committed"
        )
    }

    func test_finalDoesNotEmptyDisplayWhileCommitted() {
        var running = RunningTranscript()
        running.apply(.volatile("Hello there"))
        running.apply(.finalized("Hello there."))
        XCTAssertFalse(running.display.isEmpty)
        XCTAssertEqual(running.display, "Hello there.")
    }

    func test_displayIsTheFullUtteranceNotTheLastFinal() {
        var running = RunningTranscript()
        running.apply(.finalized("Hello there."))
        running.apply(.volatile("I wanted to talk about my week"))
        XCTAssertEqual(running.display, "Hello there. I wanted to talk about my week")
        XCTAssertEqual(running.committed, "Hello there.",
                       "committed stays the prefix; display is what we send")
    }

    func test_emptyFinalPromotesVolatile() {
        var running = RunningTranscript()
        running.apply(.volatile("uh hello"))
        running.apply(.finalized(""))
        XCTAssertEqual(running.display, "uh hello")
        XCTAssertEqual(running.committed, "uh hello")
    }

    func test_resetClearsBoth() {
        var running = RunningTranscript()
        running.apply(.finalized("Hello."))
        running.apply(.volatile("there"))
        running.reset()
        XCTAssertEqual(running.display, "")
        XCTAssertEqual(running.committed, "")
    }
}
