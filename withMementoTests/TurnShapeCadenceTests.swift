import XCTest
@testable import withMemento

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
        XCTAssertEqual(cadence.resolve(for: .nearbyOnly), .answerOpen)
        XCTAssertEqual(cadence.resolve(for: .outsideScope), .answerOpen)
    }

    /// A miss does not offer the nearest entry as a not-an-answer.
    func test_nearbyOnlyOverlay_doesNotOfferNearestEntry() {
        let overlay = TurnShapeCadence.overlayLine(shape: .answerOpen, stance: .nearbyOnly)
        XCTAssertNotNil(overlay)
        XCTAssertFalse(overlay?.contains("not-an-answer") ?? true)
        XCTAssertFalse(overlay?.contains(NoMatchLead.sentence) ?? true, "Swift writes the lead")
        XCTAssertTrue(TurnStance.nearbyOnly.promptLine.contains("Do not quote a nearer entry"))
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

    func test_overlay_journalStaysWithOneMomentThenAsks() {
        let overlay = TurnShapeCadence.overlayLine(shape: .answerOpen, stance: .journalGrounded)
        XCTAssertTrue(overlay?.contains("Stay with the moment you placed") == true)
        XCTAssertFalse(overlay?.contains("pattern") == true)
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
        XCTAssertTrue(grounded?.contains("Stay with the moment you placed") == true)
        let social = TurnShapeCadence.overlayLine(
            shape: .answerOpen, stance: .followupThread, isGrounded: false
        )
        XCTAssertTrue(social?.contains("how they are") == true)
    }
}
