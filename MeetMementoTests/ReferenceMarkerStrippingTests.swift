import XCTest
@testable import MeetMemento

/// The `[ref N]` labels in the context block are an internal handle for
/// `citedRefs`, not a citation style — but they sit in the model's context as
/// the naming convention for entries, so a small on-device model leaks them
/// into prose. Nothing downstream strips them (`RichTextParser` handles only
/// bold/italic/bullets), so whatever the model writes reaches the screen.
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
