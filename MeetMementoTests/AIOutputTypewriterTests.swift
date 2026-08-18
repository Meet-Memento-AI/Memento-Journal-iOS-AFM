import XCTest
import SwiftUI
@testable import MeetMemento

/// Pins the adaptive typewriter (spec 029): the pure reveal curve in
/// `AIOutputComponent.revealStep`, the stable-prefix split the incremental
/// parse cache keys on, and the line-scoped splice property of
/// `RichTextParser` that makes prefix caching safe.
final class AIOutputTypewriterTests: XCTestCase {

    /// One 14ms tick per loop iteration — mirrors `baseTickNanos`.
    private let tickSeconds = 0.014

    /// Runs the drain loop's arithmetic (no timing) and returns how many ticks
    /// it takes to reveal `remaining` characters.
    private func ticksToDrain(_ remaining: Int, isStreamComplete: Bool) -> Int {
        var left = remaining
        var ticks = 0
        while left > 0 {
            let step = AIOutputComponent.revealStep(
                remaining: left, isStreamComplete: isStreamComplete
            )
            XCTAssertGreaterThan(step, 0, "drain must always make progress")
            XCTAssertLessThanOrEqual(step, left, "step must never overshoot the target")
            left -= step
            ticks += 1
            if ticks > 10_000 {
                XCTFail("drain did not terminate for remaining=\(remaining)")
                break
            }
        }
        return ticks
    }

    // MARK: - Reveal curve

    /// While the model is streaming the bubble snaps to the available body.
    func test_liveStream_snapsToRemaining() {
        for remaining in 1..<AIOutputComponent.catchUpThreshold {
            XCTAssertEqual(
                AIOutputComponent.revealStep(remaining: remaining, isStreamComplete: false),
                remaining,
                "remaining=\(remaining)"
            )
        }
        XCTAssertEqual(
            AIOutputComponent.revealStep(remaining: 500, isStreamComplete: false),
            500
        )
    }

    func test_zeroRemaining_revealsNothing() {
        XCTAssertEqual(AIOutputComponent.revealStep(remaining: 0, isStreamComplete: false), 0)
        XCTAssertEqual(AIOutputComponent.revealStep(remaining: 0, isStreamComplete: true), 0)
    }

    /// More backlog never reveals fewer characters per tick.
    func test_curveIsMonotonic() {
        for complete in [false, true] {
            var previous = 0
            for remaining in 0...5_000 {
                let step = AIOutputComponent.revealStep(
                    remaining: remaining, isStreamComplete: complete
                )
                XCTAssertGreaterThanOrEqual(
                    step, previous,
                    "curve dipped at remaining=\(remaining), complete=\(complete)"
                )
                previous = step
            }
        }
    }

    /// Live snap is at least as fast as the post-final catch-up curve.
    func test_liveSnap_isAtLeastAsFastAsCompletionDrain() {
        for remaining in 0...5_000 {
            XCTAssertGreaterThanOrEqual(
                AIOutputComponent.revealStep(remaining: remaining, isStreamComplete: false),
                AIOutputComponent.revealStep(remaining: remaining, isStreamComplete: true),
                "remaining=\(remaining)"
            )
        }
    }

    /// The headline property: once the stream ends, ANY remainder up to
    /// 4000 characters finishes typing within 1 second at the 14ms tick — the
    /// reveal no longer runs on long after a lengthy reply has arrived.
    func test_postCompletionRemainder_drainsWithinOneSecond() {
        for remaining in 1...4_000 {
            let ticks = ticksToDrain(remaining, isStreamComplete: true)
            XCTAssertLessThanOrEqual(
                Double(ticks) * tickSeconds, 1.0,
                "remaining=\(remaining) took \(ticks) ticks"
            )
        }
    }

    /// Live snap finishes in a single tick regardless of backlog.
    func test_liveBacklog_snapsInOneTick() {
        for remaining in [120, 500, 1_000, 2_000, 4_000] {
            XCTAssertEqual(ticksToDrain(remaining, isStreamComplete: false), 1)
        }
    }

    // MARK: - Stable-prefix split

    func test_lastLineStart_noNewline_isStartIndex() {
        let text = "single line, no break"
        XCTAssertEqual(AIOutputComponent.lastLineStart(of: text), text.startIndex)
        XCTAssertEqual(AIOutputComponent.lastLineStart(of: ""), "".startIndex)
    }

    func test_lastLineStart_pointsPastTheLastNewline() {
        let text = "first\nsecond\ntrailing"
        let split = AIOutputComponent.lastLineStart(of: text)
        XCTAssertEqual(String(text[..<split]), "first\nsecond\n")
        XCTAssertEqual(String(text[split...]), "trailing")
    }

    func test_lastLineStart_trailingNewline_isEndIndex() {
        let text = "done\n"
        XCTAssertEqual(AIOutputComponent.lastLineStart(of: text), text.endIndex)
    }

    /// Prefix + suffix always reassemble the original — the split never eats
    /// or duplicates a character.
    func test_lastLineStart_splitIsLossless() {
        for text in ["", "\n", "a", "a\n", "\na", "a\nb\n\nc", "- item\n**bo"] {
            let split = AIOutputComponent.lastLineStart(of: text)
            XCTAssertEqual(String(text[..<split]) + String(text[split...]), text)
        }
    }

    // MARK: - Splice correctness

    /// The property the incremental parse relies on: `RichTextParser` is
    /// line-scoped, so parsing the stable prefix (through the last newline) and
    /// the trailing line separately, then appending, yields EXACTLY the same
    /// `AttributedString` as parsing the whole text — bullets, bold, italics,
    /// blank lines, and half-typed markers included. This is what guarantees
    /// the streamed render matches the final full-body parse.
    func test_splicedParse_equalsFullParse() {
        let baseFont = Font.body
        let boldFont = Font.body.bold()
        let color = Color.primary

        let samples = [
            "plain single line",
            "line one\nline two",
            "trailing newline\n",
            "\nleading newline",
            "blank\n\nline between",
            "- first bullet\n- second **bold** bullet\n- third *soft* point",
            "**bold** intro\nthen *italic* tail",
            // Half-typed markers at the reveal edge — the common mid-stream case.
            "finished line with **bold**\nan unclosed **marker",
            "finished line\n- a bullet still typi",
            "*italic\nsplit across lines*"
        ]

        for text in samples {
            let split = AIOutputComponent.lastLineStart(of: text)
            var spliced = RichTextParser.parse(
                String(text[..<split]), baseFont: baseFont, boldFont: boldFont, textColor: color
            )
            spliced.append(RichTextParser.parse(
                String(text[split...]), baseFont: baseFont, boldFont: boldFont, textColor: color
            ))
            let full = RichTextParser.parse(
                text, baseFont: baseFont, boldFont: boldFont, textColor: color
            )
            XCTAssertEqual(spliced, full, "splice diverged for: \(text.debugDescription)")
        }
    }
}
