import XCTest

extension XCTestCase {
    /// Enters `pin` on the lock screen. iPad shows an on-screen digit keypad
    /// (it has no digit-only system keyboard); iPhone auto-focuses a hidden
    /// number-pad field shortly after the lock screen appears, so typeText
    /// drives the OS keyboard directly.
    func enterLockPIN(_ pin: String, in app: XCUIApplication) {
        guard app.buttons["lock.keypad.0"].waitForExistence(timeout: 2) else {
            app.typeText(pin)
            return
        }
        for digit in pin {
            app.buttons["lock.keypad.\(digit)"].tap()
        }
    }
}
