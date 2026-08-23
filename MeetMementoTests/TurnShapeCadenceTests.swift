import XCTest
@testable import MeetMemento

/// Spec 037 R3 / 039 R6: every generated Ask turn Opens.
final class TurnShapeCadenceTests: XCTestCase {

    func test_everyStance_opens() {
        for stance in TurnStance.allCases {
            var cadence = TurnShapeCadence()
            XCTAssertEqual(cadence.resolve(for: stance), .answerOpen, "\(stance)")
        }
    }

    func test_helloThenJournal_bothOpen() {
        var cadence = TurnShapeCadence()
        XCTAssertEqual(cadence.resolve(for: .casual), .answerOpen)
        XCTAssertEqual(cadence.resolve(for: .journalGrounded), .answerOpen)
    }

    func test_consecutiveTurns_stillOpen() {
        var cadence = TurnShapeCadence()
        XCTAssertEqual(cadence.resolve(for: .journalGrounded), .answerOpen)
        XCTAssertEqual(cadence.resolve(for: .journalGrounded), .answerOpen)
        XCTAssertEqual(cadence.resolve(for: .sharing), .answerOpen)
        XCTAssertEqual(cadence.resolve(for: .casual), .answerOpen)
    }

    func test_noMatch_andOutsideScope_open() {
        var cadence = TurnShapeCadence()
        XCTAssertEqual(cadence.resolve(for: .noMatch), .answerOpen)
        XCTAssertEqual(cadence.resolve(for: .outsideScope), .answerOpen)
    }

    func test_reset_staysOpen() {
        var cadence = TurnShapeCadence()
        _ = cadence.resolve(for: .journalGrounded)
        cadence.reset()
        XCTAssertEqual(cadence.resolve(for: .journalGrounded), .answerOpen)
    }

    func test_overlay_nilForCasual_nonNilForSharing() {
        XCTAssertNil(TurnShapeCadence.overlayLine(shape: .answerOpen, stance: .casual))
        XCTAssertNotNil(TurnShapeCadence.overlayLine(shape: .answerOpen, stance: .sharing))
        XCTAssertNotNil(TurnShapeCadence.overlayLine(shape: .answerOpen, stance: .noMatch))
        XCTAssertNotNil(TurnShapeCadence.overlayLine(shape: .answerOpen, stance: .outsideScope))
    }

    func test_overlay_neverForbidsAQuestion() {
        for stance in TurnStance.allCases {
            let overlay = TurnShapeCadence.overlayLine(shape: .answerOpen, stance: stance)
            if let overlay {
                XCTAssertFalse(overlay.contains("Do not end with a question"), "\(stance)")
                XCTAssertFalse(overlay.contains("and stop"), "\(stance)")
                XCTAssertTrue(overlay.contains("question"), "\(stance)")
            }
        }
    }

    func test_overlay_journalIsPatternThenAsk() {
        let overlay = TurnShapeCadence.overlayLine(shape: .answerOpen, stance: .journalGrounded)
        XCTAssertTrue(overlay?.contains("pattern from the evidence") == true)
        XCTAssertTrue(overlay?.contains("one specific question") == true)
    }

    func test_overlay_aboutAppAndSocialCopy() {
        let aboutOpen = TurnShapeCadence.overlayLine(shape: .answerOpen, stance: .aboutApp)
        XCTAssertTrue(aboutOpen?.contains("what they want to look at") == true)

        let social = TurnShapeCadence.overlayLine(shape: .answerOpen, stance: .sharing)
        XCTAssertTrue(social?.contains("how they are") == true || social?.contains("what they just said") == true)
    }

    func test_overlay_followupUsesEvidenceWhenGrounded() {
        let grounded = TurnShapeCadence.overlayLine(
            shape: .answerOpen, stance: .followupThread, isGrounded: true
        )
        XCTAssertTrue(grounded?.contains("pattern from the evidence") == true)
        let social = TurnShapeCadence.overlayLine(
            shape: .answerOpen, stance: .followupThread, isGrounded: false
        )
        XCTAssertTrue(social?.contains("how they are") == true)
    }
}
