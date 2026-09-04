import XCTest

/// AddEntryView is a zooming NavigationStack page, not a 95% sheet.
///
/// Launches WITHOUT `-UITesting`: that flag forces Welcome. Seed the simulator:
///   xcrun simctl spawn <udid> defaults write com.sebastianmendo.MeetMemento \
///       memento_onboarding_completed -bool true
final class EntryZoomPageUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test_createEntry_opensAsPageNotSheet() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        RunLoop.current.run(until: Date().addingTimeInterval(2))

        openEditor(in: app)

        let back = app.buttons["journal.entryEditor.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 8), "editor back control missing")
        XCTAssertGreaterThan(
            back.frame.height / app.frame.height,
            0,
            "back control should be on-screen"
        )
        // Page, not a 95% sheet: the back control sits below the Dynamic Island,
        // not under a grabber in a detent.
        XCTAssertLessThan(back.frame.minY, 80, "editor header should pin to the page top")

        back.tap()
        XCTAssertTrue(back.waitForNonExistence(timeout: 8), "editor did not dismiss")
    }

    func test_cardOpensEditorPage() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        RunLoop.current.run(until: Date().addingTimeInterval(2))

        openEditor(in: app)

        let titleField = app.textViews["journal.entryEditor.title"].firstMatch.exists
            ? app.textViews["journal.entryEditor.title"]
            : app.textFields["journal.entryEditor.title"]
        if titleField.waitForExistence(timeout: 4) {
            titleField.tap()
            titleField.typeText("Zoom card")
        }

        let body = app.textViews["journal.entryEditor.body"]
        if body.waitForExistence(timeout: 4) {
            body.tap()
            body.typeText("Body for the card zoom test.")
        }

        let save = app.buttons["journal.entryEditor.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 4))
        save.tap()

        RunLoop.current.run(until: Date().addingTimeInterval(1.5))

        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Zoom card")).firstMatch
        if !card.waitForExistence(timeout: 8) {
            // Fallback: any journal card button that isn't chrome.
            let fallback = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Double-tap to open")).firstMatch
            XCTAssertTrue(
                card.exists || fallback.waitForExistence(timeout: 4),
                "saved card never appeared"
            )
            if card.exists { card.tap() } else { fallback.tap() }
        } else {
            card.tap()
        }

        let back = app.buttons["journal.entryEditor.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 8), "card did not open the editor page")
        back.tap()
        XCTAssertTrue(back.waitForNonExistence(timeout: 8))
    }

    private func openEditor(in app: XCUIApplication) {
        let fab = app.buttons["journal.newEntryFAB"]
        let labeledCTA = app.buttons["Write your first entry"]
        let newEntryCTA = app.buttons["New entry"]

        if fab.waitForExistence(timeout: 6), fab.isHittable {
            fab.tap()
        } else if labeledCTA.waitForExistence(timeout: 4) {
            labeledCTA.tap()
        } else if newEntryCTA.waitForExistence(timeout: 4) {
            newEntryCTA.tap()
        } else {
            XCTFail("need the new-entry FAB or empty-state CTA to open the editor")
        }
    }
}
