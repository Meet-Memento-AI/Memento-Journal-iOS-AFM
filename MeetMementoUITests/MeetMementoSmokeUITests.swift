import XCTest

final class MeetMementoSmokeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test_launch_doesNotCrash() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting"]
        app.launchEnvironment["MEETMEMENTO_UI_TEST"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
    }

    /// No accounts (spec 023) — Welcome shows a single "Get Started" CTA and
    /// the REQ-POS-001 positioning line, never Apple/Google sign-in buttons.
    func test_welcome_showsGetStartedNoAuthButtons() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting"]
        app.launchEnvironment["MEETMEMENTO_UI_TEST"] = "1"
        app.launch()

        let getStarted = app.buttons["welcome.getStarted"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 30))

        XCTAssertFalse(app.buttons["welcome.continueApple"].exists)
        XCTAssertFalse(app.staticTexts["Continue with Apple"].exists)
        XCTAssertFalse(app.staticTexts["Continue with Google"].exists)

        let positioning = app.staticTexts["welcome.positioning"]
        XCTAssertTrue(positioning.exists)
    }

    /// Tapping Get Started must move straight into onboarding (YourNameView)
    /// with no sign-in step in between (spec 023 R1/R2).
    func test_getStarted_entersOnboardingDirectly() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting"]
        app.launchEnvironment["MEETMEMENTO_UI_TEST"] = "1"
        app.launch()

        let getStarted = app.buttons["welcome.getStarted"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 30))
        XCTAssertTrue(getStarted.isHittable, "Get Started must remain a tappable control under Liquid Glass")
        getStarted.tap()

        let firstNameField = app.textFields["First name"]
        XCTAssertTrue(firstNameField.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Let’s get you started"].exists)
        XCTAssertTrue(app.staticTexts["What should Memento call you?"].exists)
        XCTAssertTrue(app.textFields["Last name"].exists)
        XCTAssertTrue(app.buttons["onboarding.continueName"].exists)
    }
}
