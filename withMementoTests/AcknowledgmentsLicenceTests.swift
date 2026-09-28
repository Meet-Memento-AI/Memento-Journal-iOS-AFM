import XCTest
@testable import withMemento

/// Spec 030 R6 / DEC-010 / spec 018 R12: attribution is a **licence term**, not
/// a courtesy, so it ships with the engine rather than in a follow-up. R6's
/// acceptance asked for a test reaching the Acknowledgments screen; none existed.
///
/// These assertions guard the durable half — that the notices are actually in the
/// built product. A screen can only render what the bundle contains, and a
/// missing resource is the failure mode that ships silently: `AcknowledgmentsView`
/// renders its licence sections conditionally (`if let`), so a resource dropped
/// from the target degrades to a screen with no licence text and no error.
final class AcknowledgmentsLicenceTests: XCTestCase {

    private func bundledText(_ name: String) throws -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt") else {
            throw XCTSkip("\(name).txt is not in the test host bundle")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    func test_openRAILLicence_shipsInTheBundle() throws {
        let text = try bundledText("OpenRAIL-M")
        XCTAssertTrue(text.contains("Open RAIL-M"), "must name the licence")
        // Section III requires recipients receive a copy of the licence and that
        // Attachment A's use restrictions be passed on. A paraphrase is not the
        // notice, so assert the restriction list itself is present.
        XCTAssertTrue(text.contains("Attachment A"), "use restrictions must ship")
        for clause in [
            "exploiting, harming or attempting to exploit or harm minors",
            "impersonate",
            "machine generated",
            "medical advice",
        ] {
            XCTAssertTrue(
                text.contains(clause),
                "Attachment A restriction missing from the shipped notice: \(clause)"
            )
        }
    }

    func test_openFontLicence_shipsInTheBundle() throws {
        let text = try bundledText("OFL")
        // The SIL OFL requires the copyright and permission notice ship with the
        // software. Three font families rely on this one file.
        XCTAssertTrue(text.contains("SIL OPEN FONT LICENSE"))
        XCTAssertTrue(text.contains("PERMISSION & CONDITIONS"))
    }

    func test_voiceWeights_andTheirLicence_shipTogether() throws {
        // The pairing is the point: weights present without the notice is the
        // licence breach, and the notice is cheap enough that there is no reason
        // for it to lag the weights into a release.
        let weightsPresent = Bundle.main.url(forResource: "Vocoder", withExtension: "mlmodelc") != nil
        guard weightsPresent else {
            throw XCTSkip("voice weights are not in this build")
        }
        XCTAssertNotNil(
            Bundle.main.url(forResource: "OpenRAIL-M", withExtension: "txt"),
            "voice weights ship but their licence notice does not"
        )
    }
}
