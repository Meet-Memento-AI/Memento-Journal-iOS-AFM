import XCTest

/// End-to-end check for spec 018 R7's chat amendment: a completed assistant
/// reply shows a "Read aloud" button that toggles into "Stop reading aloud"
/// while that message is being spoken.
///
/// Launches WITHOUT `-UITesting`: that flag deliberately forces the Welcome
/// screen (AppStateStore's determinism gate), but this test needs the real
/// post-onboarding app. Seed the simulator once before running:
///   xcrun simctl spawn <udid> defaults write com.sebastianmendo.MeetMemento \
///       memento_onboarding_completed -bool true
final class TTSReadAloudUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test_readAloudButton_appearsAfterReply_andToggles() {
        let app = XCUIApplication()
        app.launch()

        // Navigate Journal → Chat by swiping the root pager. Tapping the
        // Journal header's "AI chat" icon works too, but the swipe needs no
        // labels at all. (Existence/hittability checks can't confirm arrival
        // — the pager keeps the offscreen page in the hierarchy and it
        // false-positives both — so swipe unconditionally and verify by
        // driving the composer below. "Chat with Memento" is unique to the
        // composer since the header icon was renamed to "AI chat".)
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        app.swipeLeft()
        RunLoop.current.run(until: Date().addingTimeInterval(1))

        // The composer idles as a button; tapping swaps in the focused field.
        XCTAssertTrue(
            tapHittableButton(labeled: "Chat with Memento", in: app, timeout: 15),
            "idle composer button not found on the chat page"
        )

        // Tapping the idle composer focuses the field (ChatInputField sets
        // isFocused = true), so typing goes straight to the focused element.
        // A multi-sentence ask so playback is still running when the test
        // taps pause — a one-liner drains before the tap lands, and the tap
        // then starts a fresh read instead of pausing.
        app.typeText("Describe what journaling can help with, in about five sentences.")

        let send = app.buttons["Send message"]
        XCTAssertTrue(send.waitForExistence(timeout: 5), "send button not found")
        send.tap()

        // The action bar (Read aloud included) only renders once the stream
        // ends, and it fades in from opacity 0 — an opacity-0 element exists
        // but is not hittable, so wait for hittability, not mere existence.
        // On-device generation can be slow; wait generously.
        if !tapHittableButton(labeled: "Read aloud", in: app, timeout: 60) {
            let q = app.buttons.matching(NSPredicate(format: "label == %@", "Read aloud"))
            let first = q.firstMatch
            XCTFail("""
            Read aloud button never became tappable. Diagnostics: \
            matches=\(q.count) exists=\(first.exists) hittable=\(first.isHittable) \
            frame=\(first.exists ? "\(first.frame)" : "n/a") \
            allButtonLabels=\(app.buttons.allElementsBoundByIndex.prefix(25).map(\.label))
            """)
            return
        }

        // Tapped → this message speaks; the button becomes Pause (tap =
        // pause/resume — the in-app button never hard-stops).
        let readAloud = app.buttons["Read aloud"]
        let pause = app.buttons["Pause reading aloud"]
        let resume = app.buttons["Resume reading aloud"]
        XCTAssertTrue(pause.waitForExistence(timeout: 10),
                      "button did not flip to the speaking (pause) state")

        // Pause/resume mid-playback is exercised OPPORTUNISTICALLY: reply
        // length is model-controlled and a short reply drains before a tap
        // can land, so a hard assertion here is unfixably flaky. The pause
        // state machine itself is unit-covered (VoicePlaybackServiceTests);
        // this covers the live wiring whenever timing allows.
        if pause.exists && pause.isHittable {
            pause.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            if resume.waitForExistence(timeout: 5) {
                // Paused for real — resume must clear the paused state.
                resume.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                let deadline = Date().addingTimeInterval(15)
                var pausedCleared = false
                while Date() < deadline {
                    if !resume.exists { pausedCleared = true; break }
                    RunLoop.current.run(until: Date().addingTimeInterval(0.5))
                }
                XCTAssertTrue(pausedCleared, "resume left the button stuck in the paused state")
            }
            // else: playback drained before/as the tap landed (the tap then
            // started a fresh read or hit idle) — acceptable; fall through.
        }

        // Whatever the pause timing, playback ends on its own → idle returns.
        XCTAssertTrue(readAloud.waitForExistence(timeout: 90),
                      "button did not return to idle after playback finished")
    }

    /// Taps the first hittable button with the given label, polling until
    /// `timeout`. Returns false if none became hittable.
    private func tapHittableButton(
        labeled label: String, in app: XCUIApplication, timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        // Match on label, not identifier — these buttons carry only an
        // accessibilityLabel, and `matching(identifier:)` never matches those.
        let query = app.buttons.matching(NSPredicate(format: "label == %@", label))
        repeat {
            let screen = app.windows.firstMatch.frame
            for index in 0..<query.count {
                let button = query.element(boundBy: index)
                // Deliberately NOT gated on isHittable: restored-history rows
                // in the chat's LazyVStack report hittable=false forever even
                // while fully visible (accessibility quirk), and the action
                // bar's fade-in races tap()'s own re-check. An existing match
                // whose frame is on-screen gets a raw coordinate tap — that
                // synthesizes a real touch through UIKit hit-testing instead.
                if button.exists {
                    let frame = button.frame
                    if !frame.isEmpty && screen.insetBy(dx: 0, dy: 40).contains(frame) {
                        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
                        guard button.exists else { break }
                        button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                        return true
                    }
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        } while Date() < deadline
        return false
    }
}
