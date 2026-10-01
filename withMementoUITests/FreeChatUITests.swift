import XCTest

/// The free-tier chat (Figma 1177:3147, spec 021 R4/R9): Upgrade and reset in
/// the header, no starter cards, and each upgrade path opening the paywall
/// that speaks to it.
///
/// `-ForceFreeTier` (DEBUG only) shows the free tier while RevenueCat is
/// switched off. Launches WITHOUT `-UITesting`, which forces Welcome. Seed the
/// simulator once before running:
///   xcrun simctl spawn <udid> defaults write com.sebmendo.withMementoAI \
///       memento_onboarding_completed -bool true
final class FreeChatUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func openChat(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        // Swipe the root pager to Chat (see ChatSendPinUITests for why a
        // swipe, not a tap).
        app.swipeLeft()
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        return app
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    func test_freeHeaderAndEmptyState() {
        let app = openChat(["-ForceFreeTier"])
        XCTAssertTrue(element(app, "chat.header.upgrade").waitForExistence(timeout: 15), "Upgrade pill missing")
        XCTAssertTrue(element(app, "chat.header.reset").exists, "reset button missing")
        XCTAssertTrue(element(app, "chat.header.journal").exists, "Journal button missing")
        XCTAssertFalse(app.buttons["Chat history"].exists, "history is Pro-only")
        XCTAssertTrue(element(app, "chat.emptyState.free").exists, "free empty state missing")
        XCTAssertFalse(element(app, "chat.header.reset").isEnabled, "nothing to reset in an empty chat")
    }

    func test_upgradeOpensTheAskPaywall() {
        let app = openChat(["-ForceFreeTier"])
        let upgrade = element(app, "chat.header.upgrade")
        XCTAssertTrue(upgrade.waitForExistence(timeout: 15))
        upgrade.tap()
        XCTAssertTrue(element(app, "paywall.purchase").waitForExistence(timeout: 10), "paywall did not open")
        // The headline follows the journal's size (PaywallContext), so accept
        // any of the Ask variants.
        let askHeadline = NSPredicate(
            format: "label == 'A chat that remembers.' OR label == 'Every entry. One conversation.'"
        )
        XCTAssertTrue(app.staticTexts.matching(askHeadline).firstMatch.exists, "Ask paywall headline missing")
    }

    func test_resetOffersUpgradeToKeepTheConversation() {
        let app = openChat(["-ForceFreeTier", "-SeedChatTranscript"])
        let reset = element(app, "chat.header.reset")
        XCTAssertTrue(reset.waitForExistence(timeout: 15))
        XCTAssertTrue(reset.isEnabled)
        reset.tap()
        let keep = app.buttons["Keep it with Pro"]
        XCTAssertTrue(keep.waitForExistence(timeout: 5), "reset confirmation missing")
        keep.tap()
        XCTAssertTrue(app.staticTexts["Worth keeping."].waitForExistence(timeout: 10))
    }

    func test_resetStartsOver() {
        let app = openChat(["-ForceFreeTier", "-SeedChatTranscript"])
        let reset = element(app, "chat.header.reset")
        XCTAssertTrue(reset.waitForExistence(timeout: 15))
        reset.tap()
        let startOver = app.buttons["Start over"]
        XCTAssertTrue(startOver.waitForExistence(timeout: 5))
        startOver.tap()
        XCTAssertTrue(element(app, "chat.emptyState.free").waitForExistence(timeout: 10), "chat was not cleared")
    }

    /// With RevenueCat off (`-DisablePaywall`, fails open), the chat is the
    /// full Pro chat: no Upgrade pill, history present.
    func test_proChatUnchangedWithoutOverride() {
        let app = openChat(["-DisablePaywall"])
        XCTAssertTrue(app.buttons["Chat history"].waitForExistence(timeout: 15))
        XCTAssertFalse(element(app, "chat.header.upgrade").exists)
    }
}
