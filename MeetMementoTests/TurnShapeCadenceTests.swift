import XCTest
@testable import MeetMemento

/// Spec 037 R3: never two B (answer-and-open) journal shapes in a row.
final class TurnShapeCadenceTests: XCTestCase {

    /// The first grounded turn now OPENS.
    ///
    /// It used to be forced to A, which made the first reply of every new
    /// conversation the tersest one the user ever sees. The A-after-B rule
    /// below is untouched — only the starting foot changed.
    func test_firstJournalTurn_opens() {
        var cadence = TurnShapeCadence()
        XCTAssertEqual(cadence.resolve(for: .journalGrounded), .answerOpen)
    }

    func test_afterAnswerOpen_nextJournalStops() {
        var cadence = TurnShapeCadence()
        XCTAssertEqual(cadence.resolve(for: .journalGrounded), .answerOpen)
        XCTAssertEqual(cadence.resolve(for: .journalGrounded), .answerStop)
    }

    func test_neverTwoOpenShapesInARow() {
        var cadence = TurnShapeCadence()
        var last: RecallTurnShape?
        for _ in 0..<12 {
            let shape = cadence.resolve(for: .journalGrounded)
            XCTAssertFalse(last == .answerOpen && shape == .answerOpen,
                           "two B shapes in a row")
            last = shape
        }
    }

    func test_nonJournalStances_doNotAdvanceCadence() {
        var cadence = TurnShapeCadence()
        XCTAssertEqual(cadence.resolve(for: .journalGrounded), .answerOpen)
        XCTAssertEqual(cadence.resolve(for: .casual), .answerStop)
        XCTAssertEqual(cadence.resolve(for: .noMatch), .answerStop)
        XCTAssertEqual(cadence.resolve(for: .followupThread), .answerStop)
        // Casual in between must not advance the journal cadence.
        XCTAssertEqual(cadence.resolve(for: .journalGrounded), .answerStop)
    }

    func test_reset_returnsToTheOpeningShape() {
        var cadence = TurnShapeCadence()
        _ = cadence.resolve(for: .journalGrounded) // B
        _ = cadence.resolve(for: .journalGrounded) // A
        cadence.reset()
        XCTAssertEqual(cadence.resolve(for: .journalGrounded), .answerOpen)
    }

    func test_overlay_onlyOnJournalGrounded() {
        XCTAssertNil(TurnShapeCadence.overlayLine(shape: .answerOpen, stance: .casual))
        let stopOverlay = TurnShapeCadence.overlayLine(shape: .answerStop, stance: .journalGrounded)
        XCTAssertTrue(stopOverlay?.contains("Do not end with a question") == true)
        // The overlay constrains the QUESTION, never the length. "answer and
        // stop" in the prompt's highest-attention slot read to the on-device
        // model as an instruction to be brief, and collapsed replies to one
        // sentence.
        XCTAssertFalse(stopOverlay?.contains("and stop") == true,
                       "shape A must not carry a brevity cue")
        XCTAssertTrue(
            TurnShapeCadence.overlayLine(shape: .answerOpen, stance: .journalGrounded)?
                .contains("one specific question") == true
        )
    }
}
