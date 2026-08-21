import XCTest

/// Guards the resting position of Chat's send choreography: the newest user
/// message must come to rest exactly 32pt below the header row.
///
/// This is the one behavioural claim the whole feature rests on — that a top
/// `safeAreaInset` shifts what `ScrollViewProxy.scrollTo(_:anchor: .top)`
/// aligns against. It cannot be unit-tested (it is UIKit scroll-view
/// behaviour), and eyeballing a screenshot with a pixel ruler is neither
/// repeatable nor precise, so it is measured here from the real hierarchy.
///
/// Launches WITHOUT `-UITesting`: that flag deliberately forces the Welcome
/// screen. Seed the simulator once before running:
///   xcrun simctl spawn <udid> defaults write com.sebastianmendo.MeetMemento \
///       memento_onboarding_completed -bool true
final class ChatSendPinUITests: XCTestCase {

    /// `AppHeaderMetrics.rowBottomPadding`.
    private let rowBottomPadding: CGFloat = 16
    /// `AppHeaderMetrics.chatPinGap`.
    private let chatPinGap: CGFloat = 32
    /// `UserBubbleSurface`'s vertical inset — the accessibility frame is the
    /// `Text`, and the bubble's edge is one padding above it.
    private let bubbleVerticalPadding: CGFloat = 16

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Guards the top `safeAreaInset` only.
    ///
    /// With an empty transcript the first row is at content offset 0 and needs
    /// no scrolling at all, so this passes even when `scrollTo` clamps outright.
    /// `test_secondMessage_…` is the one that proves the scroll.
    func test_sentMessage_restsThirtyTwoPointsBelowTheHeaderRow() {
        let app = XCUIApplication()
        app.launchArguments = ["-InstantSendScroll"]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        // Swipe the root pager rather than tapping: the pager keeps the
        // offscreen page in the hierarchy, so existence and hittability both
        // false-positive. Arrival is confirmed by driving the composer.
        app.swipeLeft()
        RunLoop.current.run(until: Date().addingTimeInterval(1))

        // Derive the header's bottom edge from the real chrome instead of
        // hardcoding a safe-area inset, so this holds on any device.
        let headerButton = app.buttons["Chat history"]
        XCTAssertTrue(headerButton.waitForExistence(timeout: 15), "chat header not found")
        let headerRowBottom = headerButton.frame.maxY + rowBottomPadding

        let sent = "Measuring where this lands."
        send(sent, in: app)

        let bubble = app.staticTexts[sent]
        XCTAssertTrue(bubble.waitForExistence(timeout: 10), "sent message never appeared")

        // Let the flight land and the reserve settle before measuring.
        RunLoop.current.run(until: Date().addingTimeInterval(2))

        let bubbleTop = bubble.frame.minY - bubbleVerticalPadding
        let expected = headerRowBottom + chatPinGap

        XCTAssertEqual(
            bubbleTop, expected, accuracy: 1.0,
            """
            User bubble did not come to rest on the pin. \
            headerRowBottom=\(headerRowBottom) expected=\(expected) actual=\(bubbleTop). \
            A value near 0 means `scrollTo(anchor: .top)` ignored the top \
            safeAreaInset and aligned to the physical top of the scroll view.
            """
        )
    }

    /// The regression guard the single-message test cannot be.
    ///
    /// Launches with a seeded transcript one full turn tall, so the second send
    /// must genuinely travel to reach the pin. That travel is the thing that
    /// broke: `scrollTo` was issued in the same runloop turn as the `@State`
    /// write that widens the reserve, so it resolved against the previous
    /// turn's layout and clamped roughly a viewport short.
    ///
    /// ⚠️ Blind spot worth knowing: this seeds a transcript but leaves
    /// `currentSessionId` nil, so it *should* also exercise the session-id mint
    /// that once scrolled the transcript to the bottom on a new chat's first
    /// reply. It does not — the on-device model is unavailable in the simulator,
    /// so generation throws, `.final` never arrives and no id is ever minted.
    /// That regression is covered in `ChatViewModelTests` instead.
    func test_secondMessage_restsThirtyTwoPointsBelowTheHeaderRow() {
        let app = XCUIApplication()
        // No `-UITesting`: it forces the Welcome screen. Seed onboarding via
        // simctl as documented above; `-SeedChatTranscript` is DEBUG-only.
        // `-InstantSendScroll`: XCUITest cannot synchronise with an animated
        // ScrollViewProxy scroll — every query issued after one blocks until it
        // times out. This asserts the resting position, which the animation
        // does not change.
        app.launchArguments = ["-SeedChatTranscript", "-InstantSendScroll"]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        app.swipeLeft()
        RunLoop.current.run(until: Date().addingTimeInterval(1))

        let headerButton = app.buttons["Chat history"]
        XCTAssertTrue(headerButton.waitForExistence(timeout: 15), "chat header not found")
        let headerRowBottom = headerButton.frame.maxY + rowBottomPadding

        let sent = "And what should I write about tomorrow?"
        send(sent, in: app)

        let bubble = app.staticTexts[sent]
        XCTAssertTrue(bubble.waitForExistence(timeout: 10), "sent message never appeared")

        // Beat 1 (~0.42s) + beat 2 (<=0.5s) + the settle window.
        //
        // Polled rather than slept: the assistant reply never completes in the
        // simulator (no on-device model), so `AILoadingState`'s `repeatForever`
        // shimmer leaves the app permanently non-idle. A single query issued
        // after a long sleep waits on quiescence that never comes; short
        // repeated queries return the frame we need regardless.
        var settled = bubble.frame.minY
        for _ in 0..<16 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            settled = bubble.frame.minY
        }

        let expected = headerRowBottom + chatPinGap
        let actual = settled - bubbleVerticalPadding

        XCTAssertEqual(
            actual, expected, accuracy: 1.0,
            """
            Second user message did not come to rest on the pin. \
            expected=\(expected) actual=\(actual). \
            A value roughly one viewport BELOW expected means `scrollTo` \
            resolved against the layout the send turn left behind and clamped — \
            the deferral in ChatMessagesView.updatePin has regressed.
            """
        )

        // The discriminator: a clamped scroll leaves the seeded turn on screen,
        // a landed one has pushed it above the header.
        let seededPrompt = app.staticTexts[Self.seededPromptText]
        if seededPrompt.exists {
            XCTAssertLessThan(
                seededPrompt.frame.maxY, headerRowBottom,
                "the transcript never scrolled — the seeded turn is still on screen"
            )
        }
    }

    private static let seededPromptText = "What have I been writing about?"

    // MARK: - Helpers

    /// Sends `text`, retrying the tap until the composer returns to its idle
    /// state.
    ///
    /// The footer rides the keyboard's animation and the send button's centre
    /// lands within a few points of the predictions bar, so a single tap is
    /// genuinely flaky. Re-sending is not a risk: `ChatViewModel.sendMessage`
    /// guards on `!isLoading`, and each retry is gated on the composer NOT
    /// having reset yet.
    private func send(_ text: String, in app: XCUIApplication) {
        let composer = app.buttons["Chat with Memento"]
        XCTAssertTrue(composer.waitForExistence(timeout: 15),
                      "idle composer button not found on the chat page")
        composer.tap()
        app.typeText(text)

        let sendButton = app.buttons["Send message"]
        XCTAssertTrue(sendButton.waitForExistence(timeout: 5), "send button not found")

        for _ in 0..<6 {
            // The composer clears and returns to its idle label once the send
            // lands — a more reliable signal than the bubble, whose text also
            // matches the draft still sitting in the field.
            if composer.exists { return }
            // Coordinate tap unconditionally: with the keyboard up the button's
            // frame sits within a few points of the predictions bar and XCTest
            // reports it as not hittable, but the coordinate tap still lands.
            sendButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        XCTAssertTrue(composer.exists,
                      "send never landed; button frame=\(sendButton.frame)")
    }
}
