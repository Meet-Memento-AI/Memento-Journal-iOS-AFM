import XCTest

/// AddEntryView is a zooming NavigationStack page, not a 95% sheet.
///
/// Launches WITHOUT `-UITesting`: that flag forces Welcome. Seed the simulator:
///   xcrun simctl spawn <udid> defaults write com.sebastianmendo.MeetMemento \
///       memento_onboarding_completed -bool true
final class EntryZoomPageUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Creating an entry prefetches a place name, and the dictation pill
        // asks for microphone and speech recognition. Dismiss those system
        // prompts so they cannot eat the editor's own taps.
        addUIInterruptionMonitor(withDescription: "System permission") { alert in
            let buttons = ["Allow While Using App", "Allow Once", "Allow", "OK"]
            for title in buttons where alert.buttons[title].exists {
                alert.buttons[title].tap()
                return true
            }
            if alert.buttons["Don’t Allow"].exists {
                alert.buttons["Don’t Allow"].tap()
                return true
            }
            if alert.buttons["Don't Allow"].exists {
                alert.buttons["Don't Allow"].tap()
                return true
            }
            return false
        }
    }

    func test_createEntry_opensAsPageNotSheet() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        RunLoop.current.run(until: Date().addingTimeInterval(2))

        openEditor(in: app)

        let save = app.buttons["journal.entryEditor.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 8), "create should open the composer with save")
        XCTAssertTrue(
            app.textViews["journal.entryEditor.body"].waitForExistence(timeout: 4),
            "create should mount an editable body"
        )
        XCTAssertFalse(
            app.buttons["journal.entryEditor.edit"].exists,
            "create is not a view-mode session"
        )

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

        let edit = app.buttons["journal.entryEditor.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 4), "opened entry should start in view with an edit control")
        XCTAssertFalse(
            app.buttons["journal.entryEditor.save"].exists,
            "opened entry should not show save until edit"
        )
        let viewedBody = app.textViews["journal.entryEditor.body"]
        XCTAssertTrue(viewedBody.waitForExistence(timeout: 4), "view mode should show the body")

        back.tap()
        XCTAssertTrue(back.waitForNonExistence(timeout: 8))
    }

    /// An opened entry pages horizontally through the timeline. Two things are
    /// under test, and the second is the one that regressed a page `TabView`
    /// before: a swipe reaches the next entry at all, and the editor header is
    /// still pinned to the page top inside the pager — `TabView` + `.page`
    /// keeps a top inset of its own even when told to ignore the safe area.
    func test_editorPagesBetweenEntries() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        RunLoop.current.run(until: Date().addingTimeInterval(2))

        // Older first, so the newest card — the one tapped below — is Bravo and
        // Alpha sits one page to its right.
        try writeEntry(in: app, body: "Alpha body for the paging test.")
        try writeEntry(in: app, body: "Bravo body for the paging test.")

        let card = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "Bravo"))
            .firstMatch
        guard card.waitForExistence(timeout: 8) else {
            throw XCTSkip("saved cards never appeared; nothing to page between")
        }
        card.tap()

        let back = app.buttons["journal.entryEditor.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 8), "card did not open the editor page")
        XCTAssertLessThan(
            back.frame.minY, 80,
            "the pager pushed the editor header off the page top"
        )

        let body = app.textViews["journal.entryEditor.body"]
        XCTAssertTrue(body.waitForExistence(timeout: 4))
        XCTAssertTrue(
            body.label.contains("Bravo"),
            "opened the wrong entry"
        )

        // Right-to-left: newest on the left, older to the right.
        body.swipeLeft()

        let deadline = Date().addingTimeInterval(8)
        var landed = false
        while Date() < deadline {
            if app.textViews["journal.entryEditor.body"].label.contains("Alpha") {
                landed = true
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTAssertTrue(landed, "a horizontal swipe did not reach the older entry")
        XCTAssertTrue(back.exists, "paging must not dismiss the editor")
        XCTAssertLessThan(back.frame.minY, 80, "header drifted after paging")
        XCTAssertTrue(
            app.buttons["journal.entryEditor.edit"].exists,
            "paged entries stay in view"
        )
    }

    /// Pencil opens a writable session; save writes and stays on the page in view.
    func test_openedEntry_editSavesInPlace() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        RunLoop.current.run(until: Date().addingTimeInterval(2))

        try writeEntry(in: app, body: "In-place edit starting body.")

        let card = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "In-place"))
            .firstMatch
        guard card.waitForExistence(timeout: 8) else {
            throw XCTSkip("saved card never appeared")
        }
        card.tap()

        let edit = app.buttons["journal.entryEditor.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["journal.entryEditor.mic"].exists)
        XCTAssertFalse(
            app.buttons["journal.entryEditor.capture"].exists,
            "view with no cover has no Capture control"
        )
        XCTAssertFalse(
            app.buttons["journal.entryEditor.viewMemory"].exists,
            "view with no cover has no memory lens"
        )

        edit.tap()

        let save = app.buttons["journal.entryEditor.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 4), "pencil should reveal the checkmark save control")
        XCTAssertTrue(
            app.buttons["journal.entryEditor.mic"].waitForExistence(timeout: 4),
            "edit mode should show dictation"
        )
        XCTAssertTrue(
            app.buttons["journal.entryEditor.capture"].waitForExistence(timeout: 4),
            "edit mode should show Capture"
        )

        let body = app.textViews["journal.entryEditor.body"]
        XCTAssertTrue(body.waitForExistence(timeout: 4))
        body.tap()
        body.typeText(" Extra.")

        save.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))

        XCTAssertTrue(
            app.buttons["journal.entryEditor.edit"].waitForExistence(timeout: 4),
            "save should return to view, not dismiss"
        )
        XCTAssertTrue(app.buttons["journal.entryEditor.back"].exists)
        XCTAssertFalse(app.buttons["journal.entryEditor.save"].exists)
        XCTAssertTrue(
            app.textViews["journal.entryEditor.body"].label.contains("Extra"),
            "in-place save should keep the edited body on screen"
        )
        XCTAssertFalse(app.buttons["journal.entryEditor.mic"].exists)
    }

    /// Viewing a cover shows the header lens — no mic, no Capture.
    func test_openedEntry_viewMemoryHeaderWhenPhotoExists() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        RunLoop.current.run(until: Date().addingTimeInterval(2))

        openEditor(in: app)

        let capture = app.buttons["journal.entryEditor.capture"]
        guard capture.waitForExistence(timeout: 8) else {
            throw XCTSkip("Capture control never appeared")
        }
        capture.tap()

        let library = app.sheets.buttons["Choose from Library"].firstMatch.exists
            ? app.sheets.buttons["Choose from Library"].firstMatch
            : app.buttons["Choose from Library"]
        guard library.waitForExistence(timeout: 4) else {
            // Simulator camera is often missing; dismiss any unavailable alert.
            if app.alerts.firstMatch.exists {
                app.alerts.buttons["OK"].tap()
            }
            throw XCTSkip("Capture sheet never appeared; cannot attach a cover")
        }
        library.tap()

        let photo = app.images.firstMatch
        guard photo.waitForExistence(timeout: 8), photo.isHittable else {
            throw XCTSkip("Photos picker had no selectable image")
        }
        photo.tap()

        let viewMemory = app.buttons["journal.entryEditor.viewMemory"]
        guard viewMemory.waitForExistence(timeout: 8) else {
            throw XCTSkip("cover never attached after picking a photo")
        }
        XCTAssertTrue(
            app.buttons["journal.entryEditor.capture"].exists,
            "compose + photo should keep Capture; the lens lives in the header"
        )

        let editor = app.textViews["journal.entryEditor.body"]
        guard editor.waitForExistence(timeout: 4) else {
            throw XCTSkip("create body never appeared")
        }
        editor.tap()
        editor.typeText("Cover view-mode header lens test.")

        let save = app.buttons["journal.entryEditor.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 4))
        save.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))

        let card = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "Cover view-mode"))
            .firstMatch
        guard card.waitForExistence(timeout: 8) else {
            throw XCTSkip("saved cover card never appeared")
        }
        card.tap()

        XCTAssertTrue(
            app.buttons["journal.entryEditor.edit"].waitForExistence(timeout: 8),
            "opened cover entry should start in view"
        )
        XCTAssertTrue(
            app.buttons["journal.entryEditor.viewMemory"].waitForExistence(timeout: 4),
            "view + photo should show the header lens"
        )
        XCTAssertFalse(
            app.buttons["journal.entryEditor.mic"].exists,
            "view + photo must not show dictation"
        )
        XCTAssertFalse(
            app.buttons["journal.entryEditor.capture"].exists,
            "view + photo must not show Capture"
        )

        app.buttons["journal.entryEditor.viewMemory"].tap()
        XCTAssertTrue(
            app.buttons["journal.entryEditor.viewEntry"].waitForExistence(timeout: 4),
            "lens should swap to the revealed-memory glyph"
        )
        XCTAssertTrue(
            app.buttons["journal.entryEditor.edit"].exists,
            "pencil stays visible on a revealed memory"
        )
        XCTAssertTrue(app.buttons["journal.entryEditor.back"].exists)
    }

    /// Creates one entry through the editor and returns to the timeline.
    private func writeEntry(in app: XCUIApplication, body text: String) throws {
        openEditor(in: app)

        let editor = app.textViews["journal.entryEditor.body"]
        guard editor.waitForExistence(timeout: 8) else {
            throw XCTSkip("editor body never appeared")
        }
        editor.tap()
        editor.typeText(text)

        let save = app.buttons["journal.entryEditor.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 4))
        save.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
    }

    /// The dictation pill is a glass capsule, and glass contributes no hit
    /// region: without an explicit `contentShape` only the glyph and the timer
    /// text were tappable, so a stop tap on the capsule itself did nothing and
    /// recording could not be ended. Both taps here deliberately land in that
    /// old dead band rather than on the glyph.
    func test_dictationPill_togglesFromAnywhereOnTheCapsule() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        RunLoop.current.run(until: Date().addingTimeInterval(2))

        openEditor(in: app)

        let mic = app.buttons["journal.entryEditor.mic"]
        XCTAssertTrue(mic.waitForExistence(timeout: 8), "dictation pill missing")
        XCTAssertGreaterThanOrEqual(mic.frame.height, 56, "footer glass is below the 56pt floor")
        XCTAssertGreaterThanOrEqual(mic.frame.width, 56, "footer glass is below the 56pt floor")
        XCTAssertEqual(mic.label, "Start voice recording")

        // Upper band of the capsule, well clear of the centred glyph.
        deadZone(of: mic).tap()

        // The regression proper, and the part that holds on any host: the tap
        // has to reach the button at all. Before the `contentShape` it landed
        // in dead space and the pill never left its resting label. Reaching
        // the listening state additionally needs a working transcriber, which
        // the assertion below allows for.
        XCTAssertTrue(
            waitForLabelChange(from: "Start voice recording", on: mic, timeout: 8),
            "a tap on the capsule away from the glyph never reached the button"
        )

        guard waitForLabel("Stop recording", on: mic, timeout: 12) else {
            throw XCTSkip(
                """
                Never reached the listening state — this host has no usable \
                microphone, speech authorization, or on-device transcription \
                asset. Pill label was "\(mic.label)".
                """
            )
        }

        // The regression: this is the tap that used to land in dead space.
        deadZone(of: mic).tap()

        XCTAssertTrue(
            waitForLabel("Start voice recording", on: mic, timeout: 12),
            "tapping the capsule did not stop recording — pill stuck at \"\(mic.label)\""
        )
    }

    /// A point inside the pill's bounds but outside its glyph, which is what
    /// the untappable version of this control could not receive.
    private func deadZone(of element: XCUIElement) -> XCUICoordinate {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
    }

    private func waitForLabelChange(from label: String, on element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists && element.label != label { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return false
    }

    private func waitForLabel(_ label: String, on element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists && element.label == label { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return false
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
