import XCTest
@testable import MeetMemento

/// Spec 037 R3 / ask@12: thread-level Open/Stop bit. Never two Opens in a row.
final class TurnShapeCadenceTests: XCTestCase {

    func test_firstJournalTurn_opens() {
        var cadence = TurnShapeCadence()
        XCTAssertEqual(cadence.resolve(for: .journalGrounded), .answerOpen)
    }

    func test_firstCasualTurn_opens() {
        var cadence = TurnShapeCadence()
        XCTAssertEqual(cadence.resolve(for: .casual), .answerOpen)
    }

    func test_afterAnswerOpen_nextJournalStops() {
        var cadence = TurnShapeCadence()
        XCTAssertEqual(cadence.resolve(for: .journalGrounded), .answerOpen)
        XCTAssertEqual(cadence.resolve(for: .journalGrounded), .answerStop)
    }

    func test_neverTwoOpenShapesInARow() {
        var cadence = TurnShapeCadence()
        var last: RecallTurnShape?
        let stances: [TurnStance] = [.journalGrounded, .casual, .sharing, .aboutApp, .followupThread]
        for i in 0..<12 {
            let shape = cadence.resolve(for: stances[i % stances.count])
            XCTAssertFalse(last == .answerOpen && shape == .answerOpen,
                           "two Open shapes in a row")
            last = shape
        }
    }

    /// Casual after a journal Open is Stop and **does** advance the bit, so
    /// the next journal turn may Open again.
    func test_casualAfterJournalOpen_stopsAndAdvancesBit() {
        var cadence = TurnShapeCadence()
        XCTAssertEqual(cadence.resolve(for: .journalGrounded), .answerOpen)
        XCTAssertEqual(cadence.resolve(for: .casual), .answerStop)
        XCTAssertEqual(cadence.resolve(for: .journalGrounded), .answerOpen)
    }

    func test_noMatch_doesNotFlipTheBit() {
        var cadence = TurnShapeCadence()
        XCTAssertEqual(cadence.resolve(for: .journalGrounded), .answerOpen)
        XCTAssertEqual(cadence.resolve(for: .noMatch), .answerStop)
        // Bit still Open, so the next participating turn Stops.
        XCTAssertEqual(cadence.resolve(for: .casual), .answerStop)
    }

    func test_outsideScope_doesNotFlipTheBit() {
        var cadence = TurnShapeCadence()
        XCTAssertEqual(cadence.resolve(for: .casual), .answerOpen)
        XCTAssertEqual(cadence.resolve(for: .outsideScope), .answerStop)
        XCTAssertEqual(cadence.resolve(for: .sharing), .answerStop)
    }

    func test_reset_returnsToTheOpeningShape() {
        var cadence = TurnShapeCadence()
        _ = cadence.resolve(for: .journalGrounded) // Open
        _ = cadence.resolve(for: .journalGrounded) // Stop
        cadence.reset()
        XCTAssertEqual(cadence.resolve(for: .casual), .answerOpen)
    }

    func test_overlay_nonNilForCasualAndSharing() {
        XCTAssertNotNil(TurnShapeCadence.overlayLine(shape: .answerOpen, stance: .casual))
        XCTAssertNotNil(TurnShapeCadence.overlayLine(shape: .answerStop, stance: .casual))
        XCTAssertNotNil(TurnShapeCadence.overlayLine(shape: .answerOpen, stance: .sharing))
        XCTAssertNotNil(TurnShapeCadence.overlayLine(shape: .answerStop, stance: .sharing))
    }

    func test_overlay_nilForForceStopStances() {
        XCTAssertNil(TurnShapeCadence.overlayLine(shape: .answerStop, stance: .noMatch))
        XCTAssertNil(TurnShapeCadence.overlayLine(shape: .answerOpen, stance: .outsideScope))
    }

    func test_overlay_journalAndSocialCopy() {
        let stopOverlay = TurnShapeCadence.overlayLine(shape: .answerStop, stance: .journalGrounded)
        XCTAssertTrue(stopOverlay?.contains("Do not end with a question") == true)
        XCTAssertFalse(stopOverlay?.contains("and stop") == true,
                       "shape Stop must not carry a brevity cue")
        XCTAssertTrue(
            TurnShapeCadence.overlayLine(shape: .answerOpen, stance: .journalGrounded)?
                .contains("one specific question") == true
        )

        let casualOpen = TurnShapeCadence.overlayLine(shape: .answerOpen, stance: .casual)
        XCTAssertTrue(casualOpen?.contains("how they are") == true)
        XCTAssertTrue(casualOpen?.contains("Never about the journal unless they brought it up") == true)

        let socialStop = TurnShapeCadence.overlayLine(shape: .answerStop, stance: .sharing)
        XCTAssertTrue(socialStop?.contains("follow what they just said") == true)
        XCTAssertFalse(socialStop?.contains("and stop") == true)

        let aboutOpen = TurnShapeCadence.overlayLine(shape: .answerOpen, stance: .aboutApp)
        XCTAssertTrue(aboutOpen?.contains("what they want to look at") == true)
    }

    func test_overlay_followupUsesEvidenceWhenGrounded() {
        let grounded = TurnShapeCadence.overlayLine(
            shape: .answerOpen, stance: .followupThread, isGrounded: true
        )
        XCTAssertTrue(grounded?.contains("something in the evidence") == true)
        let social = TurnShapeCadence.overlayLine(
            shape: .answerOpen, stance: .followupThread, isGrounded: false
        )
        XCTAssertTrue(social?.contains("how they are") == true)
    }
}
