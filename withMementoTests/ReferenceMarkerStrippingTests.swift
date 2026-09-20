import XCTest
@testable import MeetMemento

/// The `[ref N]` labels in the context block are an internal handle for
/// `citedRefs`, not a citation style — but they sit in the model's context as
/// the naming convention for entries, so a small on-device model leaks them
/// into prose. `RichTextParser` leaves `[n]` as plain text (not a markdown
/// link); the stripper is the backstop so leaked markers never reach the screen.
///
/// These pin the backstop. Inline citations return in a later release, at which
/// point this whole surface goes away.
final class ReferenceMarkerStrippingTests: XCTestCase {

    private func strip(_ s: String) -> String {
        FoundationModelsIntelligenceService.strippingReferenceMarkers(s)
    }

    // MARK: - The forms the model actually emits

    func test_stripsBracketedRefMarker() {
        XCTAssertEqual(
            strip("You kept coming back to the move [ref 2]."),
            "You kept coming back to the move."
        )
    }

    func test_stripsParenthesisedRefMarker() {
        XCTAssertEqual(
            strip("That week was heavy (ref 1)."),
            "That week was heavy."
        )
    }

    func test_stripsBareRefMarker() {
        XCTAssertEqual(
            strip("You wrote about it again in ref 3."),
            "You wrote about it again in."
        )
    }

    func test_stripsBareSquareBracketNumber() {
        XCTAssertEqual(
            strip("The pattern shows up twice [2]."),
            "The pattern shows up twice."
        )
    }

    func test_isCaseInsensitive() {
        XCTAssertEqual(strip("Something [Ref 2]."), "Something.")
        XCTAssertEqual(strip("Something [REF 2]."), "Something.")
    }

    func test_stripsRefLists() {
        XCTAssertEqual(strip("Twice that month [ref 1, 2]."), "Twice that month.")
        XCTAssertEqual(strip("Twice that month [ref 1 and 2]."), "Twice that month.")
        XCTAssertEqual(strip("Twice that month [1, 2]."), "Twice that month.")
    }

    func test_stripsAbbreviatedAndHashForms() {
        XCTAssertEqual(strip("As noted [ref. 2]."), "As noted.")
        XCTAssertEqual(strip("As noted [ref #2]."), "As noted.")
    }

    // MARK: - Position and tidy-up

    func test_stripsMidSentenceAndClosesTheGap() {
        XCTAssertEqual(
            strip("The move [ref 2] came up again later."),
            "The move came up again later."
        )
    }

    func test_stripsMultipleMarkersInOneBody() {
        XCTAssertEqual(
            strip("First that [ref 1], then this [ref 2], then the other [ref 3]."),
            "First that, then this, then the other."
        )
    }

    func test_leavesNoDoubledSpacesOrSpaceBeforePunctuation() {
        let out = strip("Work was hard [ref 1] , and home was quieter [ref 2] .")
        XCTAssertFalse(out.contains("  "), "no doubled spaces: \(out)")
        XCTAssertFalse(out.contains(" ,"), "no space before comma: \(out)")
        XCTAssertFalse(out.contains(" ."), "no space before period: \(out)")
    }

    func test_stripsMarkerAcrossMultipleLines() {
        let out = strip("You noticed the quiet [ref 1].\n\nThen it shifted [ref 2].")
        XCTAssertFalse(out.lowercased().contains("ref"))
        XCTAssertTrue(out.contains("\n\n"), "paragraph breaks must survive: \(out)")
    }

    // MARK: - Schema field names leaked as prose (observed live 2026-08-23)

    /// The model writes `citedRefs` into `body` instead of into the property.
    /// These four strings are verbatim tails of real replies from the QA pass.
    func test_stripsTrailingCitedRefsFieldName() {
        for tail in ["citedRefs:", "citedRefs: 1.", "citedRefs:[1]", "citedRefs: 1, 2"] {
            let body = "That pattern has stayed with you. What are you holding onto now?\n\n\(tail)"
            let out = strip(body)
            XCTAssertFalse(out.lowercased().contains("citedrefs"), "leaked field name survived: \(out)")
            XCTAssertTrue(out.hasSuffix("What are you holding onto now?"),
                          "stripping must not eat the reply: \(out)")
        }
    }

    func test_stripsHeadingFieldNames() {
        let out = strip("heading1: You and the fog. What stayed with you?")
        XCTAssertFalse(out.lowercased().contains("heading1"), out)
        XCTAssertTrue(out.hasPrefix("You and the fog."), out)
    }

    /// A bracket pair with no digits in it — the number-bearing patterns cannot
    /// match these. Observed live as a trailing `[,]` on its own line.
    func test_stripsBracketPairsWithoutNumbers() {
        for junk in ["[,]", "[]", "[ref]", "[-]"] {
            let out = strip("What's carrying you now, beyond the things you've written?\n\(junk)")
            XCTAssertFalse(out.contains(junk), "\(junk) survived: \(out)")
            XCTAssertTrue(out.hasSuffix("written?"), out)
        }
    }

    // MARK: - Truncation wreckage (observed in the chat eval gate 2026-08-23)

    func test_stripsControlTokenAndEverythingAfterIt() {
        let out = strip("What are you holding steady right now?**} <ctrl46>Memento leans into the quiet, the")
        XCTAssertEqual(out, "What are you holding steady right now?")
    }

    func test_stripsDanglingHeadingTheReplyNeverFilledIn() {
        let body = "You’re the one who knows the rhythm of those quiet shifts.\n### July 19, 2026 *"
        XCTAssertEqual(strip(body), "You’re the one who knows the rhythm of those quiet shifts.")
    }

    func test_stripsBareTrailingHeading() {
        XCTAssertEqual(strip("Hey there, what’s something new you’ve tried lately?\n###"),
                       "Hey there, what’s something new you’ve tried lately?")
    }

    /// A heading with a body after it is real content, not wreckage.
    func test_keepsAHeadingThatHasContentAfterIt() {
        let body = "You went up the mountain.\n### August 2, 2026\n*“Drove out to Mount Tamalpais.”*\nWhat stayed with you?"
        XCTAssertEqual(strip(body), body)
    }

    /// Regression, and the reason the dangling-heading pattern is as fussy as it
    /// is. Replies are frequently a *single line* with the heading inline, and a
    /// pattern anchored on "### … end of string" then matched from the heading
    /// all the way to the end — deleting the quote, the reflection and the
    /// closing question. Five clean replies lost their question this way; the
    /// eval gate caught it as a jump in `rule.noOpen` from 5 to 17.
    func test_keepsAnInlineHeadingAndEverythingAfterIt() {
        let body = "You’ve been tracing quiet shifts. ### August 2, 2026 *“Drove out to Mount "
            + "Tamalpais on Saturday with Maya.”* The fog lifting matched something in you. "
            + "What is it you’re holding onto right now?"
        XCTAssertEqual(strip(body), body)
    }

    // MARK: - What must NOT be touched

    func test_bodyWithoutMarkersIsUnchanged() {
        let clean = "You wrote about the move on March 5th, and again two weeks later. What made it stick?"
        XCTAssertEqual(strip(clean), clean)
    }

    func test_doesNotStripOrdinaryNumbersOrDates() {
        let s = "You wrote 3 entries that week, and on March 5, 2026 you sounded lighter."
        XCTAssertEqual(strip(s), s)
    }

    func test_doesNotStripWordsMerelyStartingWithRef() {
        let s = "You kept reflecting on it, and the refresh helped."
        XCTAssertEqual(strip(s), s)
    }

    func test_emptyBodyStaysEmpty() {
        XCTAssertEqual(strip(""), "")
    }
}
