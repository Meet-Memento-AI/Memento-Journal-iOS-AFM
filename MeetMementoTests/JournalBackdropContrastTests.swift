import XCTest
@testable import MeetMemento

final class JournalBackdropContrastTests: XCTestCase {

    func test_nearBlackPhoto_keepsZeroScrim() {
        let params = JournalBackdropContrast.parameters(
            srgb: (0.05, 0.05, 0.05)
        )
        XCTAssertEqual(params.scrimOpacity, 0, accuracy: 0.001)
        XCTAssertEqual(params.blurStrength, JournalBackdropShader.blurStrength)
        XCTAssertEqual(params.saturation, JournalBackdropShader.saturation)
    }

    func test_whitePhoto_doesNotRaiseScrim() {
        let params = JournalBackdropContrast.parameters(
            srgb: (1, 1, 1)
        )
        XCTAssertEqual(params.scrimOpacity, JournalBackdropShader.scrimOpacity, accuracy: 0.001)
        XCTAssertEqual(params.saturation, JournalBackdropShader.saturation)
    }

    func test_restingScrim_staysAtTheToken() {
        let params = JournalBackdropContrast.parameters(
            srgb: (0, 0, 0)
        )
        XCTAssertEqual(params.scrimOpacity, JournalBackdropShader.scrimOpacity, accuracy: 0.001)
    }

    func test_increaseContrast_startsAtFloor() {
        let params = JournalBackdropContrast.parameters(
            srgb: (0.05, 0.05, 0.05),
            increaseContrast: true
        )
        XCTAssertGreaterThanOrEqual(params.scrimOpacity, JournalBackdropShader.increaseContrastFloor)
    }

    func test_reduceTransparency_zeroesBlur() {
        let params = JournalBackdropContrast.parameters(
            srgb: (0.05, 0.05, 0.05),
            reduceTransparency: true
        )
        XCTAssertEqual(params.blurStrength, 0)
        XCTAssertEqual(params.scrimOpacity, JournalBackdropShader.scrimOpacity, accuracy: 0.001)
    }

    func test_editorDefaults_nearBlack_keepsZeroScrimAndLightBlur() {
        let params = JournalBackdropContrast.parameters(
            srgb: (0.05, 0.05, 0.05),
            base: JournalBackdropShader.editorDefaults
        )
        XCTAssertEqual(
            params.scrimOpacity,
            JournalBackdropShader.editorDefaults.scrimOpacity,
            accuracy: 0.001
        )
        XCTAssertEqual(
            params.blurStrength,
            JournalBackdropShader.editorDefaults.blurStrength,
            accuracy: 0.001
        )
        XCTAssertEqual(params.saturation, JournalBackdropShader.editorDefaults.saturation)
    }

    func test_editorDefaults_reduceTransparency_zeroesBlur() {
        let params = JournalBackdropContrast.parameters(
            srgb: (0.05, 0.05, 0.05),
            base: JournalBackdropShader.editorDefaults,
            reduceTransparency: true
        )
        XCTAssertEqual(params.blurStrength, 0)
        XCTAssertEqual(
            params.scrimOpacity,
            JournalBackdropShader.editorDefaults.scrimOpacity,
            accuracy: 0.001
        )
        XCTAssertEqual(params.saturation, JournalBackdropShader.editorDefaults.saturation)
    }

    func test_editorDefaults_whitePhoto_keepsZeroScrim() {
        let params = JournalBackdropContrast.parameters(
            srgb: (1, 1, 1),
            base: JournalBackdropShader.editorDefaults
        )
        XCTAssertEqual(
            params.scrimOpacity,
            JournalBackdropShader.editorDefaults.scrimOpacity,
            accuracy: 0.001
        )
        XCTAssertEqual(
            params.blurStrength,
            JournalBackdropShader.editorDefaults.blurStrength,
            accuracy: 0.001
        )
        XCTAssertEqual(params.saturation, JournalBackdropShader.editorDefaults.saturation)
    }

    // MARK: - Chrome tint

    /// `scrimFactor` 0 is the case that matters: the View memory reveal
    /// dissolves the scrim off, so the raw cover is what the glass refracts.
    private func chromeTint(
        srgb: (Double, Double, Double),
        scrimFactor: Double,
        increaseContrast: Bool = false,
        reduceTransparency: Bool = false
    ) -> (tint: JournalChromeTint, contrast: Double) {
        let sample = JournalBackdropSample(red: srgb.0, green: srgb.1, blue: srgb.2)
        let params = JournalBackdropShader.editorDefaults
        let tint = JournalBackdropContrast.chromeTint(
            sample: sample,
            params: params,
            scrimFactor: scrimFactor,
            increaseContrast: increaseContrast,
            reduceTransparency: reduceTransparency
        )
        let backdrop = JournalBackdropContrast.chromeBackdrop(
            sample: sample,
            params: params,
            scrimFactor: scrimFactor
        )
        return (tint, JournalBackdropContrast.chromeContrast(tint: tint, over: backdrop))
    }

    func test_chromeTint_darkCover_staysAtTheAestheticFloor() {
        // Already legible without help, so the wash is decoration only.
        let resolved = chromeTint(srgb: (0.05, 0.05, 0.05), scrimFactor: 1)
        XCTAssertEqual(
            resolved.tint.opacity,
            JournalBackdropShader.chromeTintFloor,
            accuracy: 0.001
        )
        XCTAssertGreaterThanOrEqual(resolved.contrast, JournalBackdropShader.minimumContrast)
    }

    func test_chromeTint_brightBareCover_thickensUntilWhiteIsLegible() {
        let resolved = chromeTint(srgb: (0.55, 0.55, 0.55), scrimFactor: 0)
        XCTAssertGreaterThan(resolved.tint.opacity, JournalBackdropShader.chromeTintFloor)
        XCTAssertLessThan(
            resolved.tint.opacity,
            JournalBackdropShader.chromeTintCeiling,
            "a mid-bright cover should be solved, not capped"
        )
        XCTAssertGreaterThanOrEqual(resolved.contrast, JournalBackdropShader.minimumContrast)
    }

    /// The reveal's whole reason for tinting: dissolving the scrim off can
    /// only make the chrome's job harder, never easier.
    func test_chromeTint_revealingTheCoverNeverWeakensTheWash() {
        let bright = (0.9, 0.85, 0.7)
        let treated = chromeTint(srgb: bright, scrimFactor: 1)
        let bare = chromeTint(srgb: bright, scrimFactor: 0)
        XCTAssertGreaterThanOrEqual(bare.tint.opacity, treated.tint.opacity)
    }

    /// A near-white cover with the scrim dissolved off is past what a
    /// translucent wash can fix — white ink needs the backdrop darkened to
    /// roughly 0.47 sRGB, which is an opaque panel, not glass. The search
    /// caps instead of chasing it, and the treated state (one tap away, and
    /// where the entry is actually read) is the one carrying the WCAG
    /// guarantee via `parameters(srgb:)`.
    func test_chromeTint_extremeCover_capsRatherThanBecomingAPanel() {
        let resolved = chromeTint(srgb: (1, 1, 1), scrimFactor: 0, increaseContrast: true)
        XCTAssertEqual(
            resolved.tint.opacity,
            JournalBackdropShader.chromeTintCeiling,
            accuracy: 0.001
        )
    }

    func test_chromeTint_increaseContrast_thickensTheWash() {
        // 0.39 is inside the band where the floor misses AAA but the ceiling
        // can still solve it after chromeTintDepth was lowered for dreamier
        // frost. A brighter fixture would cap; a darker one already passes
        // at the aesthetic floor.
        let plain = chromeTint(srgb: (0.39, 0.39, 0.39), scrimFactor: 0)
        let raised = chromeTint(srgb: (0.39, 0.39, 0.39), scrimFactor: 0, increaseContrast: true)
        XCTAssertGreaterThan(raised.tint.opacity, plain.tint.opacity)
        XCTAssertGreaterThanOrEqual(
            raised.contrast,
            JournalBackdropShader.chromeIncreasedContrast
        )
    }

    func test_chromeTint_reduceTransparency_raisesTheFloor() {
        let resolved = chromeTint(
            srgb: (0.05, 0.05, 0.05),
            scrimFactor: 1,
            reduceTransparency: true
        )
        XCTAssertGreaterThanOrEqual(
            resolved.tint.opacity,
            JournalBackdropShader.chromeReduceTransparencyFloor
        )
    }

    /// The wash carries the cover's cast without becoming a colour block.
    func test_chromeTint_keepsSomeOfTheCoversCastButNotAllOfIt() {
        let warm = chromeTint(srgb: (0.9, 0.5, 0.2), scrimFactor: 0).tint
        XCTAssertGreaterThan(warm.red, warm.blue, "the cover's warmth should survive")

        let sample = JournalBackdropSample(red: 0.9, green: 0.5, blue: 0.2)
        let backdrop = JournalBackdropContrast.chromeBackdrop(
            sample: sample,
            params: JournalBackdropShader.editorDefaults,
            scrimFactor: 0
        )
        XCTAssertLessThan(
            warm.red - warm.blue,
            backdrop.r - backdrop.b,
            "and should be muted well below the cover's own chroma"
        )
    }

    func test_photoChromeTintKeep_dropsAboutSeventyPercentOfTheWash() {
        XCTAssertEqual(
            JournalBackdropShader.photoChromeTintKeep,
            0.3,
            accuracy: 0.001
        )
        let tint = JournalChromeTint(red: 0.2, green: 0.2, blue: 0.2, opacity: 0.4)
        XCTAssertEqual(
            tint.opacity * JournalBackdropShader.photoChromeTintKeep,
            0.12,
            accuracy: 0.001
        )
    }

    // MARK: - Prominence frost

    func test_prominentFrost_restsInTheWelcomeBand() {
        let opacity = JournalBackdropShader.prominentFrostOpacity(
            increaseContrast: false,
            reduceTransparency: false
        )
        XCTAssertEqual(opacity, JournalBackdropShader.prominentFrostFloor, accuracy: 0.001)
        XCTAssertGreaterThan(opacity, 0.24, "at least as dense as Welcome Get Started")
        XCTAssertLessThan(opacity, 0.5, "must stay glass, not a charcoal slab")
    }

    func test_prominentFrost_reduceTransparency_raisesTheFloor() {
        let opacity = JournalBackdropShader.prominentFrostOpacity(
            increaseContrast: false,
            reduceTransparency: true
        )
        XCTAssertGreaterThanOrEqual(
            opacity,
            JournalBackdropShader.chromeReduceTransparencyFloor
        )
        XCTAssertLessThanOrEqual(opacity, JournalBackdropShader.chromeTintCeiling)
    }

    func test_prominentFrost_increaseContrast_thickensWithoutBecomingAPanel() {
        let plain = JournalBackdropShader.prominentFrostOpacity(
            increaseContrast: false,
            reduceTransparency: false
        )
        let raised = JournalBackdropShader.prominentFrostOpacity(
            increaseContrast: true,
            reduceTransparency: false
        )
        XCTAssertGreaterThan(raised, plain)
        XCTAssertLessThanOrEqual(raised, JournalBackdropShader.chromeTintCeiling)
    }
}
