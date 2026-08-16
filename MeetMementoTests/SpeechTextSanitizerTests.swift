import XCTest
@testable import MeetMemento

/// One fixture per stripped pattern (mirrors the per-pattern style of
/// scripts/ci/speakability_lint.py's selftest). The sanitizer is a
/// *transformer* for markdown-bearing chat prose — distinct from spec 018 R9's
/// SpeakabilityLinter, which validates reflection prose that should never have
/// contained markdown in the first place.
final class SpeechTextSanitizerTests: XCTestCase {

    private func sanitize(_ s: String) -> String {
        SpeechTextSanitizer.sanitize(s)
    }

    // MARK: - Emphasis

    func test_unwrapsBold() {
        XCTAssertEqual(sanitize("That **matters** to you."), "That matters to you.")
    }

    func test_unwrapsItalic() {
        XCTAssertEqual(sanitize("A *quiet* week."), "A quiet week.")
    }

    func test_unwrapsUnderscoreEmphasis() {
        XCTAssertEqual(sanitize("It was _heavy_ then."), "It was heavy then.")
    }

    func test_keepsIntraWordUnderscores() {
        XCTAssertEqual(sanitize("snake_case_name stays"), "snake_case_name stays")
    }

    func test_unwrapsBackticks() {
        XCTAssertEqual(sanitize("Try `journaling` daily."), "Try journaling daily.")
    }

    // MARK: - Links and URLs

    func test_markdownLinkKeepsTextDropsURL() {
        XCTAssertEqual(sanitize("See [this entry](https://example.com/e/1) again."),
                       "See this entry again.")
    }

    func test_bareURLRemoved() {
        XCTAssertEqual(sanitize("More at https://example.com today."), "More at today.")
    }

    // MARK: - Structure

    func test_headingMarkerDropped() {
        XCTAssertEqual(sanitize("## A pattern\nYou noticed it."), "A pattern\nYou noticed it.")
    }

    func test_bulletMarkersDropped() {
        XCTAssertEqual(sanitize("- First thing\n* Second thing\n• Third thing"),
                       "First thing\nSecond thing\nThird thing")
    }

    func test_orderedListMarkersDropped() {
        XCTAssertEqual(sanitize("1. Sleep\n2. Walks"), "Sleep\nWalks")
    }

    // MARK: - Citations and Sources (delegation fixtures — the full matrices
    // live in ReferenceMarkerStrippingTests and the RichTextParser tests)

    func test_citationMarkersRemoved() {
        XCTAssertEqual(sanitize("You wrote about the move [ref 2]."),
                       "You wrote about the move.")
        XCTAssertEqual(sanitize("It resurfaced twice [3]."), "It resurfaced twice.")
    }

    func test_sourcesBlockRemoved() {
        XCTAssertEqual(sanitize("You slept badly.\n\n**Sources:**\n- March 5th - work stress"),
                       "You slept badly.")
    }

    // MARK: - Emoji

    func test_emojiRemoved() {
        XCTAssertEqual(sanitize("Proud of you 🎉 truly ✨"), "Proud of you truly")
    }

    func test_digitsSurviveEmojiPass() {
        XCTAssertEqual(sanitize("3 walks over #2 weeks *"), "3 walks over #2 weeks *")
    }

    // MARK: - Whitespace

    func test_blankLineRunsCollapse() {
        XCTAssertEqual(sanitize("One.\n\n\n\nTwo."), "One.\n\nTwo.")
    }

    func test_spaceRunsCollapse() {
        XCTAssertEqual(sanitize("One    two."), "One two.")
    }

    func test_cleanTextPassesThroughUnchanged() {
        let clean = "You mentioned feeling calmer after the walk. That seems worth keeping."
        XCTAssertEqual(sanitize(clean), clean)
    }

    // MARK: - speakableText

    func test_speakableTextAddsTerminalPunctuationToHeadings() {
        let result = SpeechTextSanitizer.speakableText(
            heading1: "A quieter week",
            heading2: "What changed?",
            body: "You slept more."
        )
        XCTAssertEqual(result, "A quieter week.\n\nWhat changed?\n\nYou slept more.")
    }

    func test_speakableTextSkipsNilAndEmptyParts() {
        XCTAssertEqual(
            SpeechTextSanitizer.speakableText(heading1: nil, heading2: "", body: "Just the body."),
            "Just the body."
        )
    }

    func test_speakableTextSanitizesEveryPart() {
        let result = SpeechTextSanitizer.speakableText(
            heading1: "**Bold heading**",
            heading2: nil,
            body: "Body with [ref 1]."
        )
        XCTAssertEqual(result, "Bold heading.\n\nBody with.")
    }
}
