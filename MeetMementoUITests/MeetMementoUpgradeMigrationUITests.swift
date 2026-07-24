import XCTest

/// Exercises spec 023 R5 (existing-user migration) through a real app launch,
/// not just a direct `migrateFromPriorAccountIfNeeded()` call in a unit test.
/// `-SeedUpgradeFixture` (consumed only by `AppStateStore`, double-gated on
/// `-UITesting`) writes pre-023 local evidence — cached name + a configured
/// PIN lock, no onboarding-complete flag — before the app's normal launch
/// path runs, simulating a device upgrading from the account-based build.
final class MeetMementoUpgradeMigrationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Migrated users must never see Welcome/onboarding again, and their
    /// configured lock must stay intact (spec 023 R5 acceptance).
    func test_upgradeFixture_skipsOnboarding_landsOnIntactLockScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-SeedUpgradeFixture"]
        app.launchEnvironment["MEETMEMENTO_UI_TEST"] = "1"
        app.launch()

        // Lock screen (PIN configured by the seed) must appear directly —
        // proving migration ran and marked onboarding complete without
        // showing Welcome or onboarding first.
        let firstPinDigit = app.buttons["PIN digit 1 of 4"]
        XCTAssertTrue(firstPinDigit.waitForExistence(timeout: 15))

        // No auth-era or onboarding UI reachable.
        XCTAssertFalse(app.buttons["welcome.getStarted"].exists)
        XCTAssertFalse(app.textFields["First name"].exists)

        // The migrated PIN lock is real, not bypassed — a wrong PIN must not
        // unlock. The hidden PIN field auto-focuses shortly after the lock
        // screen appears; typeText drives the OS keyboard directly rather
        // than tapping the (purely visual) digit slot buttons.
        app.typeText("9999") // seeded PIN is 4829 — this is deliberately wrong

        let pinError = app.staticTexts["Incorrect PIN"]
        _ = pinError.waitForExistence(timeout: 5)
        XCTAssertTrue(firstPinDigit.exists)
        XCTAssertFalse(app.buttons["journal.newEntryFAB"].exists)
    }

    /// The other half of the same matrix cell: the *correct* migrated PIN
    /// must actually unlock — proving the lock isn't just displayed but is
    /// wired to the real, migrated credential. Asserts the lock screen goes
    /// away, not any specific downstream Journal content state (loading/
    /// empty/error), since what's rendered after unlock depends on
    /// `EntryViewModel`'s network fetch — out of scope for this migration
    /// test and not guaranteed reachable in a sandboxed simulator anyway.
    func test_upgradeFixture_correctPIN_unlocksToJournal() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-SeedUpgradeFixture"]
        app.launchEnvironment["MEETMEMENTO_UI_TEST"] = "1"
        app.launch()

        let firstPinDigit = app.buttons["PIN digit 1 of 4"]
        XCTAssertTrue(firstPinDigit.waitForExistence(timeout: 15))

        app.typeText("4829") // matches the PIN seedUpgradeFixture() saves

        let unlocked = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: firstPinDigit)
        wait(for: [unlocked], timeout: 10)
    }

    /// No lock-screen exit path may reference sign-out (spec 023 R6 — the
    /// account-era escape hatch is fully replaced by device-passcode
    /// fallback). Static text search across the locked screen's visible
    /// hierarchy is the most direct way to assert an absence.
    func test_lockScreen_hasNoSignOutReference() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-SeedUpgradeFixture"]
        app.launchEnvironment["MEETMEMENTO_UI_TEST"] = "1"
        app.launch()

        XCTAssertTrue(app.buttons["PIN digit 1 of 4"].waitForExistence(timeout: 15))

        XCTAssertFalse(app.staticTexts["Sign Out"].exists)
        XCTAssertFalse(app.buttons["Sign Out"].exists)
        XCTAssertFalse(app.staticTexts["Sign out"].exists)
        XCTAssertFalse(app.buttons["Sign out"].exists)

        // The R6 replacement escape hatch — device-passcode fallback — must
        // be present and reachable directly from PIN entry (not just from
        // the no-security-configured emergency view).
        XCTAssertTrue(app.buttons["Forgot PIN? Use device passcode"].exists)
    }

    /// spec 023 R4's "Delete Everything" must produce a state indistinguishable
    /// from a fresh install — driven end to end through the real Settings UI
    /// (drawer → Settings → Delete Everything → both confirmations), not by
    /// calling `AppStateStore.deleteEverything()` directly.
    func test_deleteEverything_relaunchIndistinguishableFromFreshInstall() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-SeedUpgradeFixture"]
        app.launchEnvironment["MEETMEMENTO_UI_TEST"] = "1"
        app.launch()

        XCTAssertTrue(app.buttons["PIN digit 1 of 4"].waitForExistence(timeout: 15))
        app.typeText("4829")

        let menuButton = app.buttons["Menu"]
        XCTAssertTrue(menuButton.waitForExistence(timeout: 10))
        menuButton.tap()

        let settingsRow = app.buttons["drawer.settings"]
        XCTAssertTrue(settingsRow.waitForExistence(timeout: 5))
        settingsRow.tap()

        let deleteRow = app.buttons["settings.deleteEverything"]
        XCTAssertTrue(deleteRow.waitForExistence(timeout: 10))
        deleteRow.tap()

        let continueButton = app.buttons["Continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5))
        continueButton.tap()

        let finalConfirmButton = app.buttons["Delete Everything"]
        XCTAssertTrue(finalConfirmButton.waitForExistence(timeout: 5))
        finalConfirmButton.tap()

        // Same running process: appState flips to the fresh-install routing
        // immediately, no relaunch needed to observe it.
        let getStarted = app.buttons["welcome.getStarted"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 10))

        // Persisted, not just in-memory: terminate and relaunch with NO
        // -UITesting flag at all this time. -UITesting alone always forces
        // Welcome regardless of persisted state (see AppStateStore's
        // isUiTestRun determinism override) — that would make this check
        // pass even if deleteEverything() were a no-op. Omitting it forces
        // initializeAppState() to read real UserDefaults, so Welcome only
        // appears here if onboarding-complete was genuinely cleared.
        app.terminate()
        let relaunched = XCUIApplication()
        relaunched.launch()
        XCTAssertTrue(relaunched.buttons["welcome.getStarted"].waitForExistence(timeout: 15))
    }
}
