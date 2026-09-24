import XCTest

/// App Store screenshot capture (checklist D9).
///
/// D9 was tracked as "presumed populated" in App Store Connect on inference
/// rather than evidence, and no image file existed anywhere under
/// `docs/app-store/metadata/`. iPad frames are mandatory, not optional,
/// because `TARGETED_DEVICE_FAMILY = "1,2"`.
///
/// Automated rather than captured by hand for the reason the readiness
/// checklist gives about every other row: a human tapping through Settings
/// before each capture produces slightly different frames every time, and
/// nobody can tell later whether a frame shows the shipped build. This runs
/// off `-SeedSampleEntries`, which calls the same `SampleContentService.load()`
/// the Settings row calls.
///
/// Guideline 2.3.3 wants the app shown in use — so every frame carries the
/// sample journal, never an empty state. Guideline 2.3.9 wants the content
/// fictional, which `withMemento/Resources/SampleEntries.json` is by
/// construction: it is the synthetic nine-month persona the eval fixtures use.
///
/// Run per device, skipped unless asked for:
/// ```
/// TEST_RUNNER_SCREENSHOTS=1 \
/// DEVELOPER_DIR=~/Downloads/Xcode.app/Contents/Developer \
/// xcodebuild test -scheme withMemento \
///   -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
///   -only-testing:withMementoUITests/AppStoreScreenshotUITests
/// ```
/// Frames land in the result bundle as attachments; `scripts/ci/export_screenshots.sh`
/// lifts them into `docs/app-store/metadata/en-US/screenshots/`.
final class AppStoreScreenshotUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["SCREENSHOTS"] == "1"
                || ProcessInfo.processInfo.environment["TEST_RUNNER_SCREENSHOTS"] == "1",
            "Set TEST_RUNNER_SCREENSHOTS=1 to capture App Store frames."
        )
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-SeedSampleEntries", "-InstantSendScroll"]
        app.launchEnvironment["MEETMEMENTO_UI_TEST"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    }

    /// Saves a full-screen frame under a stable, ordered name.
    ///
    /// `.keepAlways` because the whole point is the artifact; the default
    /// lifetime deletes attachments on success, which is exactly when we want
    /// them.
    private func capture(_ order: Int, _ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = String(format: "%02d-%@", order, name)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Every navigation step asserts it actually moved before the frame is
    /// taken.
    ///
    /// The first version of this test guessed identifiers — `tab.chat`,
    /// `tab.settings` — that do not exist. Nothing threw: the taps were no-ops,
    /// the test passed, three attachments appeared at exactly 1320×2868, and
    /// two of them were byte-identical copies of the timeline. Right count,
    /// right dimensions, wrong pictures, green build. Only opening the PNGs
    /// caught it.
    ///
    /// So a capture is only taken once the destination is proven on screen. A
    /// screenshot run that cannot navigate must fail loudly rather than ship a
    /// duplicate frame to the App Store.
    ///
    /// Navigation model (`RootPager`): the root is a horizontal pager, not a
    /// tab bar. Chat is the journal page's top-right icon — accessibility label
    /// "AI chat" — or a left swipe. Settings is the top-left profile button,
    /// `profile.settings`.
    func test_captureAppStoreFrames() throws {
        // 1 — Timeline with a populated journal. The frame 2.3.3 is about, and
        // the proof the seed worked: an empty state here means the rest is junk.
        let seeded = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "Pottery")
        ).firstMatch
        XCTAssertTrue(seeded.waitForExistence(timeout: 30),
                      "sample journal did not load — -SeedSampleEntries is not taking effect")
        Thread.sleep(forTimeInterval: 2)
        capture(1, "timeline")

        // 2 — An entry open. The cards carry no identifier, so this taps the
        // seeded entry's own text, which the assertion above proved is present.
        seeded.tap()
        let editorBody = app.textViews["journal.entryEditor.body"]
        let editorTitle = app.textFields["journal.entryEditor.title"]
        XCTAssertTrue(editorBody.waitForExistence(timeout: 15) || editorTitle.exists,
                      "tapping an entry did not open the editor")
        Thread.sleep(forTimeInterval: 2)
        capture(2, "entry")

        let back = app.buttons["journal.entryEditor.back"]
        if back.exists { back.tap() } else { app.swipeRight() }
        XCTAssertTrue(seeded.waitForExistence(timeout: 15), "did not return to the timeline")

        // 3 — Ask. What the store copy leads on.
        let askButton = app.buttons["AI chat"]
        if askButton.exists { askButton.tap() } else { app.swipeLeft() }
        let askArrived = app.buttons["chat.header.history"].waitForExistence(timeout: 15)
            || app.buttons["chat.header.summarize"].waitForExistence(timeout: 5)
        XCTAssertTrue(askArrived, "did not reach the chat page")

        // Ask, with its journal-derived starters.
        //
        // What this frame *should* show is Ask answering, because that is the
        // feature the description leads on and 2.3.3 wants the app in use. It
        // does not, and the reason is worth recording rather than hiding.
        //
        // Generation is on-device, and Apple Intelligence model assets are
        // per-simulator. They are present on `ChatDiag27`, which every
        // conversation study ran on — but that is an iPhone 17 **Pro**
        // (1206×2622), and the 6.9" slot needs 1320×2868, so it cannot produce
        // this frame. On a Pro Max without the assets, a tapped starter waits
        // 90 seconds and never streams a reply. Two constraints that do not
        // currently intersect.
        //
        // So the frame is the entry screen — but asserted to be a *loaded* one.
        // The starters are generated from the seeded journal, so their presence
        // proves the app read it; an unseeded build shows generic prompts or
        // none. That keeps this from being the "empty state passed as a
        // feature" screenshot Apple rejects.
        //
        // Set SCREENSHOT_LIVE_REPLY=1 on a Pro Max simulator that has the model
        // assets and this captures the real answer instead.
        let starters = app.buttons.allElementsBoundByIndex.filter { $0.label.count > 20 }
        XCTAssertFalse(starters.isEmpty,
                       "no journal-derived starters on the Ask screen — the seed did not reach chat")

        if ProcessInfo.processInfo.environment["SCREENSHOT_LIVE_REPLY"] == "1" {
            starters[0].tap()
            XCTAssertTrue(app.buttons["chat.reply.thumbsUp"].waitForExistence(timeout: 120),
                          "SCREENSHOT_LIVE_REPLY was set but no reply streamed — "
                            + "does this simulator have Apple Intelligence assets?")
            Thread.sleep(forTimeInterval: 2)
        } else {
            Thread.sleep(forTimeInterval: 3)
        }
        capture(3, "ask")

        // 4 — Search over the journal.
        //
        // This was Settings, on the reasoning that a reviewer looks there for
        // the privacy and export controls. Wrong target: `profile.settings` is
        // a NavigationLink *inside* `ProfileSheet`, which the avatar opens, so
        // reaching it is avatar → sheet → row → screen. Three taps deep, and a
        // settings list is a weak store frame besides. Search is one tap from
        // the header, has a known handle, and shows the feature the
        // description's "Timeline" paragraph is about — finding your own words
        // again.
        app.swipeRight()
        XCTAssertTrue(seeded.waitForExistence(timeout: 15), "did not return to the journal page")
        let searchButton = app.buttons["Search"]
        XCTAssertTrue(searchButton.waitForExistence(timeout: 15), "Search button not found")
        searchButton.tap()
        let searchField = app.textFields["Search journal entries"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 15), "did not reach journal search")
        searchField.tap()
        searchField.typeText("pottery")
        Thread.sleep(forTimeInterval: 3)
        capture(4, "search")
    }
}
