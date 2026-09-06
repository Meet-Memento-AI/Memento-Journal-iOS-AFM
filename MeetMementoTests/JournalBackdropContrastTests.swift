import XCTest
@testable import MeetMemento

final class JournalBackdropContrastTests: XCTestCase {

    func test_nearBlackPhoto_keepsFigmaScrim_andPassesWCAG() {
        let params = JournalBackdropContrast.parameters(
            srgb: (0.05, 0.05, 0.05)
        )
        XCTAssertEqual(params.scrimOpacity, JournalBackdropShader.scrimOpacity, accuracy: 0.001)
        XCTAssertEqual(params.blurStrength, JournalBackdropShader.blurStrength)
        XCTAssertEqual(params.saturation, JournalBackdropShader.saturation)
        let contrast = JournalBackdropContrast.contrast(
            srgb: (0.05, 0.05, 0.05),
            saturation: params.saturation,
            scrimOpacity: params.scrimOpacity
        )
        XCTAssertGreaterThanOrEqual(contrast, JournalBackdropShader.minimumContrast)
    }

    func test_whitePhoto_raisesScrimUntilWCAG() {
        let params = JournalBackdropContrast.parameters(
            srgb: (1, 1, 1)
        )
        XCTAssertGreaterThan(params.scrimOpacity, JournalBackdropShader.scrimOpacity)
        let contrast = JournalBackdropContrast.contrast(
            srgb: (1, 1, 1),
            saturation: params.saturation,
            scrimOpacity: params.scrimOpacity
        )
        XCTAssertGreaterThanOrEqual(contrast, JournalBackdropShader.minimumContrast)
        XCTAssertEqual(params.saturation, JournalBackdropShader.saturation)
    }

    func test_neverDropsBelowFigmaScrim() {
        let params = JournalBackdropContrast.parameters(
            srgb: (0, 0, 0)
        )
        XCTAssertGreaterThanOrEqual(params.scrimOpacity, JournalBackdropShader.scrimOpacity)
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
        let contrast = JournalBackdropContrast.contrast(
            srgb: (0.05, 0.05, 0.05),
            saturation: params.saturation,
            scrimOpacity: params.scrimOpacity
        )
        XCTAssertGreaterThanOrEqual(contrast, JournalBackdropShader.minimumContrast)
    }

    func test_editorDefaults_nearBlack_keepsEditorScrimAndBlur() {
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
        let contrast = JournalBackdropContrast.contrast(
            srgb: (0.05, 0.05, 0.05),
            saturation: params.saturation,
            scrimOpacity: params.scrimOpacity
        )
        XCTAssertGreaterThanOrEqual(contrast, JournalBackdropShader.minimumContrast)
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

    func test_editorDefaults_whitePhoto_raisesScrimUntilWCAG() {
        let params = JournalBackdropContrast.parameters(
            srgb: (1, 1, 1),
            base: JournalBackdropShader.editorDefaults
        )
        XCTAssertGreaterThan(
            params.scrimOpacity,
            JournalBackdropShader.editorDefaults.scrimOpacity
        )
        XCTAssertGreaterThanOrEqual(
            params.blurStrength,
            JournalBackdropShader.editorDefaults.blurStrength
        )
        XCTAssertEqual(params.saturation, JournalBackdropShader.editorDefaults.saturation)
        let contrast = JournalBackdropContrast.contrast(
            srgb: (1, 1, 1),
            saturation: params.saturation,
            scrimOpacity: params.scrimOpacity
        )
        XCTAssertGreaterThanOrEqual(contrast, JournalBackdropShader.minimumContrast)
    }
}
