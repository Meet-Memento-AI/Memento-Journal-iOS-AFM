import XCTest

/// Settings → Read Aloud (spec 018 R7 chat amendment): the voice section is
/// reachable, and a picked speaking speed persists.
///
/// Same launch posture as TTSReadAloudUITests: NO `-UITesting` (that forces
/// Welcome); seed the simulator once with
///   xcrun simctl spawn <udid> defaults write com.sebastianmendo.MeetMemento \
///       memento_onboarding_completed -bool true
final class VoiceSettingsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test_voiceSettings_reachable_andRateSelectionPersists() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))

        // Journal header avatar ("Menu") → profile sheet → Settings.
        let menu = app.buttons["Menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 15), "avatar Menu button not found")
        menu.tap()

        let settingsRow = app.buttons["profile.settings"].firstMatch
        let settingsAny = app.descendants(matching: .any)["profile.settings"].firstMatch
        if settingsRow.waitForExistence(timeout: 10) {
            settingsRow.tap()
        } else if settingsAny.waitForExistence(timeout: 5) {
            settingsAny.tap()
        } else {
            XCTFail("profile.settings row not found in profile sheet")
            return
        }

        // Hub → Read Aloud.
        let voiceRow = app.descendants(matching: .any)["settings.voice"].firstMatch
        XCTAssertTrue(voiceRow.waitForExistence(timeout: 10), "settings.voice row not found")
        voiceRow.tap()

        // A catalog voice row proves VoiceSettingsView rendered. The old
        // "Automatic" row is gone: the roster is four bundled neural voices with
        // nothing to resolve between (specs 030 R4, 033 R1; DEC-011/DEC-012).
        let firstVoice = app.descendants(matching: .any)["settings.voice.option.F1"].firstMatch
        XCTAssertTrue(firstVoice.waitForExistence(timeout: 10), "voice settings did not open")

        // Exactly four voices, no more — the roster is fixed and enforced by
        // which style vectors are vendored at all (spec 030 R4).
        for id in ["F1", "F2", "M1", "M3"] {
            XCTAssertTrue(
                app.descendants(matching: .any)["settings.voice.option.\(id)"].firstMatch.exists,
                "expected voice \(id) in the picker"
            )
        }
        XCTAssertFalse(
            app.descendants(matching: .any)["settings.voice.automatic"].firstMatch.exists,
            "the Automatic row should be gone"
        )

        // Pick a non-default speed and verify it sticks across a relaunch.
        let fastRow = app.descendants(matching: .any)["settings.voice.rate.fast"].firstMatch
        XCTAssertTrue(fastRow.waitForExistence(timeout: 10), "Fast rate row not found")
        fastRow.tap()
        XCTAssertTrue(fastRow.isSelected, "Fast rate did not select on tap")

        app.terminate()
        app.launch()
        XCTAssertTrue(menu.waitForExistence(timeout: 15))
        menu.tap()
        if settingsRow.waitForExistence(timeout: 10) {
            settingsRow.tap()
        } else {
            _ = settingsAny.waitForExistence(timeout: 5)
            settingsAny.tap()
        }
        XCTAssertTrue(voiceRow.waitForExistence(timeout: 10))
        voiceRow.tap()
        let fastAfterRelaunch = app.descendants(matching: .any)["settings.voice.rate.fast"].firstMatch
        XCTAssertTrue(fastAfterRelaunch.waitForExistence(timeout: 10))
        XCTAssertTrue(fastAfterRelaunch.isSelected, "Fast rate did not persist across relaunch")
    }
}
