//
//  Spec029PerfHelperTests.swift
//  MeetMementoTests
//
//  Pure decision helpers introduced by spec 029: turn-timing bookkeeping, the
//  narration watchdog's adaptive tick, the speech-authorization fast path, and
//  the sentence chunker's first-sentence fast path.
//

import Speech
import XCTest
@testable import MeetMemento

// MARK: - TurnTimings

final class TurnTimingsTests: XCTestCase {

    func test_stageDurations_andSummaryOrder() {
        var timings = TurnTimings()
        let clock = ContinuousClock()
        let t0 = clock.now
        timings.begin(turnAt: t0)
        timings.start(.micStop, at: t0)
        timings.end(.micStop, at: t0 + .milliseconds(180))
        timings.start(.modelFirstToken, at: t0 + .milliseconds(200))
        timings.end(.modelFirstToken, at: t0 + .milliseconds(840))
        timings.mark(.ttsFirstAudio, at: t0 + .milliseconds(1900))

        XCTAssertEqual(timings.duration(of: .micStop), .milliseconds(180))
        XCTAssertEqual(timings.duration(of: .modelFirstToken), .milliseconds(640))
        let summary = timings.summaryLine()
        XCTAssertEqual(summary, "stop 180ms | ttft 640ms | 1st-audio@1.9s",
                       "stages print in canonical order; marks use @offset form")
    }

    func test_endWithoutStart_isIgnored() {
        var timings = TurnTimings()
        timings.end(.persist, at: ContinuousClock().now)
        XCTAssertNil(timings.duration(of: .persist))
    }

    func test_total_sumsOnlyRecordedStages() {
        var timings = TurnTimings()
        let clock = ContinuousClock()
        let t0 = clock.now
        timings.start(.prepSafety, at: t0)
        timings.end(.prepSafety, at: t0 + .milliseconds(10))
        timings.start(.prepRetrieve, at: t0)
        timings.end(.prepRetrieve, at: t0 + .milliseconds(90))
        XCTAssertEqual(timings.total(of: [.prepSafety, .prepClassify, .prepRetrieve]),
                       .milliseconds(100))
    }

    func test_format_msBelowOneSecond_secondsAbove() {
        XCTAssertEqual(TurnTimings.format(.milliseconds(950)), "950ms")
        XCTAssertEqual(TurnTimings.format(.milliseconds(1900)), "1.9s")
    }

    func test_liveClock_secondBeginTurn_isIgnoredUntilRelease() {
        let clock = LiveTurnClock.shared
        clock.resetForTesting()
        clock.beginTurn(heldOpen: true)
        clock.start(.prepSafety)
        clock.end(.prepSafety)
        clock.beginTurn() // must not reset
        clock.finishAndLog() // held open — still recording
        clock.mark(.firstSentence)
        clock.releaseAndLog()
        clock.resetForTesting()
    }
}

// MARK: - Adaptive watchdog tick (spec 029 R4)

@MainActor
final class NarrationWatchdogDelayTests: XCTestCase {

    func test_coarseTick_farFromThePause() {
        XCTAssertEqual(NarrationCoordinator.watchdogDelay(secondsSinceChange: 0),
                       250_000_000)
        XCTAssertEqual(NarrationCoordinator.watchdogDelay(secondsSinceChange: 1.0),
                       250_000_000)
    }

    func test_fineTick_onceTheSendIsImminent() {
        let pause = NarrationCoordinator.autoSendPause
        XCTAssertEqual(NarrationCoordinator.watchdogDelay(secondsSinceChange: pause - 0.3),
                       100_000_000)
        XCTAssertEqual(NarrationCoordinator.watchdogDelay(secondsSinceChange: pause),
                       100_000_000)
        XCTAssertEqual(NarrationCoordinator.watchdogDelay(secondsSinceChange: pause + 5),
                       100_000_000)
    }
}

// MARK: - Speech authorization fast path (spec 029 R4)

@MainActor
final class SpeechAuthMappingTests: XCTestCase {

    func test_mapping_coversEveryStatus() {
        XCTAssertEqual(SpeechService.mapSpeechAuth(.authorized), .authorized)
        XCTAssertEqual(SpeechService.mapSpeechAuth(.notDetermined), .notDetermined)
        XCTAssertEqual(SpeechService.mapSpeechAuth(.denied), .denied)
        XCTAssertEqual(SpeechService.mapSpeechAuth(.restricted), .denied,
                       "restricted must fail closed like denied — only notDetermined may trigger the XPC request")
    }
}

// MARK: - Chunker first-sentence fast path (spec 029 R4)

final class StreamingSentenceChunkerFastPathTests: XCTestCase {

    func test_shortOpener_emitsImmediatelyAtBoundary() {
        var chunker = StreamingSentenceChunker()
        XCTAssertEqual(chunker.consume("Sure.", isFinal: false), ["Sure."],
                       "a boundary-complete first sentence must not wait for the merge minimum")
    }

    func test_shortOpener_midWord_stillHeld() {
        var chunker = StreamingSentenceChunker()
        XCTAssertEqual(chunker.consume("Sure", isFinal: false), [],
                       "no boundary yet — nothing to speak")
    }

    func test_openerMergedLater_remainderStillSpoken() {
        // The forward-merge rule folds the short opener into the next
        // sentence on later snapshots; the reconciliation must emit the
        // remainder exactly once and never re-emit the opener.
        var chunker = StreamingSentenceChunker()
        XCTAssertEqual(chunker.consume("Sure.", isFinal: false), ["Sure."])
        XCTAssertEqual(chunker.consume("Sure. Let's talk about", isFinal: false), [],
                       "trailing fragment still growing")
        XCTAssertEqual(chunker.consume("Sure. Let's talk about your week.", isFinal: false),
                       ["Let's talk about your week."])
        XCTAssertEqual(chunker.consume("Sure. Let's talk about your week. What stood out?",
                                       isFinal: true),
                       ["What stood out?"])
    }

    func test_openerMergedLater_finalFlushOnly() {
        var chunker = StreamingSentenceChunker()
        XCTAssertEqual(chunker.consume("Yes.", isFinal: false), ["Yes."])
        XCTAssertEqual(chunker.consume("Yes. It can help to name it.", isFinal: true),
                       ["It can help to name it."],
                       "a merged opener at final must not swallow the remainder")
    }

    func test_abbreviationOpener_isNotFastPathed() {
        var chunker = StreamingSentenceChunker()
        XCTAssertEqual(chunker.consume("E.g.", isFinal: false), [],
                       "abbreviation false-splits keep waiting for their merge")
        XCTAssertFalse(StreamingSentenceChunker.isLikelySentence("E.g."))
        XCTAssertFalse(StreamingSentenceChunker.isLikelySentence("Dr."))
        XCTAssertTrue(StreamingSentenceChunker.isLikelySentence("Sure."))
        XCTAssertTrue(StreamingSentenceChunker.isLikelySentence("Okay!"))
    }

    func test_longFirstSentence_behavesAsBefore() {
        var chunker = StreamingSentenceChunker()
        XCTAssertEqual(chunker.consume("That sounds like a lot to carry.", isFinal: false),
                       ["That sounds like a lot to carry."])
    }

    func test_firstChunk_emitsStablePrefixBeforePeriod() {
        var chunker = StreamingSentenceChunker()
        // 10 complete words + an 11th still growing — speak the prefix.
        let growing = "This has been a really heavy week for you lately and"
        XCTAssertEqual(StreamingSentenceChunker.completeWordCount(growing), 10)
        XCTAssertEqual(
            chunker.consume(growing, isFinal: false),
            ["This has been a really heavy week for you lately"]
        )
    }

    func test_firstChunk_emitsClauseAtComma() {
        var chunker = StreamingSentenceChunker()
        let clause = "This has been a really heavy week for you and your family, "
        XCTAssertGreaterThanOrEqual(
            StreamingSentenceChunker.completeWordCount(clause),
            StreamingSentenceChunker.firstClauseMinWords
        )
        let emitted = chunker.consume(clause + "and I keep thinking", isFinal: false)
        XCTAssertEqual(emitted.count, 1)
        XCTAssertTrue(emitted[0].hasSuffix(",") || emitted[0].contains("family"),
                      "first chunk should be the clause through the comma")
    }

    func test_firstChunk_holdsUntilEnoughWords() {
        var chunker = StreamingSentenceChunker()
        XCTAssertEqual(chunker.consume("This has been a really heavy", isFinal: false), [])
    }

    func test_firstChunk_thenPeriod_remainderSpokenOnce() {
        var chunker = StreamingSentenceChunker()
        let prefix = "This has been a really heavy week for you lately"
        XCTAssertEqual(chunker.consume(prefix + " and", isFinal: false), [prefix])
        XCTAssertEqual(
            chunker.consume(prefix + " and I hear you.", isFinal: false),
            ["and I hear you."]
        )
    }

    func test_stableTail_emitsWhenQueueIsDry() {
        var chunker = StreamingSentenceChunker()
        _ = chunker.consume("That sounds like a lot to carry today.", isFinal: false)
        let tail = "I keep thinking about how heavy this week has been for you"
        // 12+ complete words, no period — held without the flag.
        XCTAssertEqual(
            chunker.consume(
                "That sounds like a lot to carry today. \(tail) still",
                isFinal: false
            ),
            []
        )
        XCTAssertEqual(
            chunker.consume(
                "That sounds like a lot to carry today. \(tail) still",
                isFinal: false,
                allowStableTail: true
            ),
            [tail]
        )
    }

    func test_subsequentShortSentences_stillMergeForward() {
        var chunker = StreamingSentenceChunker()
        _ = chunker.consume("That sounds like a lot to carry today.", isFinal: false)
        // A later short fragment is NOT the session opener — the normal merge
        // rule still holds it for the following sentence.
        XCTAssertEqual(chunker.consume("That sounds like a lot to carry today. Okay.",
                                       isFinal: false), [])
        XCTAssertEqual(chunker.consume("That sounds like a lot to carry today. Okay. Let's unpack it together now.",
                                       isFinal: true),
                       ["Okay. Let's unpack it together now."])
    }
}
