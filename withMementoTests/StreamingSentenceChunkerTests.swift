import XCTest
@testable import MeetMemento

/// The chunker feeds VoicePlaybackService's per-sentence enqueue seam from
/// ChatService's *cumulative* delta bodies. The contract under test: every
/// word is spoken exactly once, in order, no matter how the cumulative
/// snapshots grow — or shrink (reference-marker stripping).
final class StreamingSentenceChunkerTests: XCTestCase {

    // MARK: - Incremental growth

    func test_holdsIncompleteTrailingSentence() {
        var chunker = StreamingSentenceChunker()
        XCTAssertEqual(chunker.consume("You mentioned feeling", isFinal: false), [])
        XCTAssertEqual(chunker.consume("You mentioned feeling calmer lately", isFinal: false), [])
    }

    func test_emitsSentenceOnceBoundaryAppears() {
        var chunker = StreamingSentenceChunker()
        _ = chunker.consume("You mentioned feeling calmer", isFinal: false)
        XCTAssertEqual(
            chunker.consume("You mentioned feeling calmer lately. And that", isFinal: false),
            ["You mentioned feeling calmer lately."]
        )
    }

    func test_doesNotReEmitSpokenSentences() {
        var chunker = StreamingSentenceChunker()
        _ = chunker.consume("First thought is here. Second one is", isFinal: false)
        let fresh = chunker.consume("First thought is here. Second one is done. Third", isFinal: false)
        XCTAssertEqual(fresh, ["Second one is done."])
    }

    func test_multipleSentencesInOneDelta() {
        var chunker = StreamingSentenceChunker()
        let fresh = chunker.consume(
            "That sounds heavy today. Rest matters a lot. What helped before?",
            isFinal: true
        )
        XCTAssertEqual(fresh, [
            "That sounds heavy today.",
            "Rest matters a lot.",
            "What helped before?",
        ])
    }

    // MARK: - Final flush

    func test_finalFlushesTrailingFragment() {
        var chunker = StreamingSentenceChunker()
        _ = chunker.consume("A full sentence lands here. And a trailing bit", isFinal: false)
        XCTAssertEqual(
            chunker.consume("A full sentence lands here. And a trailing bit", isFinal: true),
            ["And a trailing bit"]
        )
    }

    func test_finalOnEmptyBodyEmitsNothing() {
        var chunker = StreamingSentenceChunker()
        XCTAssertEqual(chunker.consume("", isFinal: true), [])
    }

    func test_finalWithWhitespaceOnlyEmitsNothing() {
        var chunker = StreamingSentenceChunker()
        XCTAssertEqual(chunker.consume("  \n ", isFinal: true), [])
    }

    // MARK: - Shrinking cumulative body

    func test_shrinkingBodyEmitsNothingAndKeepsCount() {
        var chunker = StreamingSentenceChunker()
        _ = chunker.consume("One steady sentence here. Another steady sentence here.", isFinal: false)
        XCTAssertEqual(chunker.emittedCount, 2)
        // Marker stripping shrank the cleaned body below what was spoken.
        XCTAssertEqual(chunker.consume("One steady sentence here.", isFinal: false), [])
        XCTAssertEqual(chunker.emittedCount, 2)
    }

    // MARK: - Short fragments / abbreviations

    func test_shortFragmentMergesIntoNextSentence() {
        var chunker = StreamingSentenceChunker()
        let fresh = chunker.consume("E.g. journaling before bed helps you sleep.", isFinal: true)
        XCTAssertEqual(fresh, ["E.g. journaling before bed helps you sleep."])
    }

    func test_shortTrailingPieceHeldUntilFinal() {
        var chunker = StreamingSentenceChunker()
        // "E.g." ends at a boundary but is short — must not be emitted alone
        // mid-stream, or the words that later merge behind it are never spoken.
        XCTAssertEqual(chunker.consume("E.g.", isFinal: false), [])
        XCTAssertEqual(
            chunker.consume("E.g. a short walk after lunch works.", isFinal: true),
            ["E.g. a short walk after lunch works."]
        )
    }

    func test_shortFinalSentenceStillEmitted() {
        var chunker = StreamingSentenceChunker()
        let fresh = chunker.consume("Here is one long opening sentence. Take care.", isFinal: true)
        XCTAssertEqual(fresh, ["Here is one long opening sentence.", "Take care."])
    }

    // MARK: - Punctuation and structure

    func test_punctuationRunsStayTogether() {
        var chunker = StreamingSentenceChunker()
        let fresh = chunker.consume("Really, that happened?! Tell me more about it…", isFinal: true)
        XCTAssertEqual(fresh, ["Really, that happened?!", "Tell me more about it…"])
    }

    func test_newlinesActAsBoundaries() {
        var chunker = StreamingSentenceChunker()
        let fresh = chunker.consume(
            "A first paragraph without punctuation\nA second paragraph follows here",
            isFinal: true
        )
        XCTAssertEqual(fresh, [
            "A first paragraph without punctuation",
            "A second paragraph follows here",
        ])
    }

    func test_markdownPassesThroughUntouched() {
        // Sanitizing is VoicePlaybackService.enqueue's job — the chunker must
        // not pre-strip, or the single-choke-point contract breaks.
        var chunker = StreamingSentenceChunker()
        let fresh = chunker.consume("You said **rest** felt impossible.", isFinal: true)
        XCTAssertEqual(fresh, ["You said **rest** felt impossible."])
    }

    // MARK: - Conversation first-chunk (narration)

    func test_conversationProfile_emitsPrefixAtFiveWords() {
        var chunker = StreamingSentenceChunker(profile: .conversation)
        let prefix = "Work felt pretty heavy today"
        XCTAssertEqual(
            StreamingSentenceChunker.completeWordCount(prefix + " and"),
            StreamingSentenceChunker.FirstChunkProfile.conversation.firstPrefixMinWords
        )
        XCTAssertEqual(chunker.consume(prefix + " and", isFinal: false), [prefix])
    }

    func test_readBackProfile_holdsFiveWordPrefix() {
        var chunker = StreamingSentenceChunker()
        XCTAssertEqual(
            chunker.consume("Work felt pretty heavy today and", isFinal: false),
            []
        )
    }

    func test_conversationProfile_emitsClauseAtSixWords() {
        var chunker = StreamingSentenceChunker(profile: .conversation)
        let clause = "Work felt pretty heavy today lately, "
        XCTAssertGreaterThanOrEqual(
            StreamingSentenceChunker.completeWordCount(clause),
            StreamingSentenceChunker.FirstChunkProfile.conversation.firstClauseMinWords
        )
        let emitted = chunker.consume(clause + "and I keep thinking", isFinal: false)
        XCTAssertEqual(emitted.count, 1)
        XCTAssertTrue(emitted[0].hasSuffix(",") || emitted[0].contains("lately"))
    }
}
