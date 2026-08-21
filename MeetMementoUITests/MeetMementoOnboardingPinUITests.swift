import XCTest

/// Regression coverage for the PIN-confirmation bug fixed in
/// `ConfirmPinView.swift`: on a mismatched PIN, the field used to stay
/// bound to the stale wrong digits for ~400-500ms (until an async shake
/// animation finished), silently swallowing whatever the user retyped
/// during that window. The fix clears the field synchronously on mismatch,
/// mirroring `LockScreenView`'s already-correct pattern. This test walks
/// the real onboarding flow end to end, deliberately entering a wrong PIN
/// then immediately retyping the correct one with no artificial wait, to
/// prove the retry is never swallowed.
final class MeetMementoOnboardingPinUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// iOS 27's simulator shows the keyboard's swipe-to-type introduction
    /// overlay (`UIContinuousPathIntroductionView`) the first time a keyboard
    /// appears — it carries its own "Continue" button, which is exactly why
    /// this test queries the app's buttons by accessibility identifier, never
    /// by the "Continue" label. Dismiss the overlay when present so it can't
    /// cover other controls either.
    private func dismissKeyboardIntroIfPresent(_ app: XCUIApplication) {
        let intro = app.otherElements["UIContinuousPathIntroductionView"]
        if intro.waitForExistence(timeout: 2) {
            intro.buttons["Continue"].tap()
        }
    }

    func test_confirmPin_mismatchThenImmediateCorrectRetry_succeeds() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting"]
        app.launchEnvironment["MEETMEMENTO_UI_TEST"] = "1"
        app.launch()

        // Welcome -> Get Started
        let getStarted = app.buttons["welcome.getStarted"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 15))
        getStarted.tap()

        // YourNameView — Next step is disabled until both fields are filled.
        let firstNameField = app.textFields["First name"]
        XCTAssertTrue(firstNameField.waitForExistence(timeout: 10))
        firstNameField.tap()
        dismissKeyboardIntroIfPresent(app)
        firstNameField.typeText("Ada")

        let lastNameField = app.textFields["Last name"]
        lastNameField.tap()
        lastNameField.typeText("Lovelace")

        app.buttons["onboarding.continueName"].tap()

        // LearnAboutYourselfView — Continue (checkmark) works with empty text.
        let learnContinue = app.buttons["onboarding.continueLearn"]
        XCTAssertTrue(learnContinue.waitForExistence(timeout: 10))
        learnContinue.tap()

        // ThemeConfirmationView — all categories render; empty reflection means
        // nothing is preselected, so pick one theme to enable the CTA.
        let themeChip = app.buttons["onboarding.theme.anxiety"]
        XCTAssertTrue(themeChip.waitForExistence(timeout: 15))
        themeChip.tap()
        app.buttons["onboarding.continueThemes"].tap()

        // FaceIDView — take the PIN path.
        let createPinInstead = app.buttons["Create a PIN instead"]
        XCTAssertTrue(createPinInstead.waitForExistence(timeout: 10))
        createPinInstead.tap()

        // SetupPinView — unlike the lock screen, nothing here auto-focuses
        // the hidden keyboard field; tapping the PIN entry row is required.
        let setPinButton = app.buttons["Set PIN"]
        XCTAssertTrue(setPinButton.waitForExistence(timeout: 10))
        app.buttons["PIN entry"].tap()
        app.typeText("4829")
        XCTAssertTrue(setPinButton.waitForExistence(timeout: 5))
        setPinButton.tap()

        // ConfirmPinView — same explicit tap-to-focus, then a mismatched PIN.
        let confirmButton = app.buttons["Confirm PIN"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 10))
        app.buttons["PIN entry"].tap()
        app.typeText("1111") // deliberately wrong — setup PIN was 4829

        let mismatchError = app.staticTexts["PINs don't match. Please try again."]
        XCTAssertTrue(mismatchError.waitForExistence(timeout: 5))

        // The regression: immediately retype the correct PIN with no wait.
        // Before the fix, these keystrokes landed during the ~400-500ms
        // window where the field was still bound to the stale wrong digits
        // and got silently discarded.
        app.typeText("4829")

        // Success navigates away from ConfirmPinView entirely.
        let advanced = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: confirmButton)
        wait(for: [advanced], timeout: 10)
    }
}
