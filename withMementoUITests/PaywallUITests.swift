import XCTest

/// Spec 021 R3: Restore Purchases is visible without scrolling, including at
/// the largest accessibility text size. Runs on the DEBUG preview harness
/// (`-UITesting -PaywallPreview`), so RevenueCat is never configured.
final class PaywallUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchPaywall(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-PaywallPreview"] + extraArguments
        app.launch()
        XCTAssertTrue(
            app.descendants(matching: .any)["paywall.purchase"].firstMatch.waitForExistence(timeout: 15),
            "paywall did not present"
        )
        return app
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    func test_footerIsVisibleWithoutScrolling_andAnnualIsSelected() {
        let app = launchPaywall()
        for id in ["paywall.purchase", "paywall.restore", "paywall.terms", "paywall.privacy", "paywall.disclosure"] {
            XCTAssertTrue(element(app, id).isHittable, "\(id) is not visible without scrolling")
        }
        XCTAssertTrue(element(app, "paywall.comparison").exists, "Free / Pro table missing")
        XCTAssertTrue(element(app, "paywall.plan.annual").isSelected, "annual should be selected first")
        XCTAssertFalse(element(app, "paywall.plan.monthly").isSelected)
    }

    func test_restoreIsVisibleWithoutScrolling_atLargestTextSize() {
        let app = launchPaywall(extraArguments: [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ])
        XCTAssertTrue(element(app, "paywall.restore").isHittable, "Restore scrolled off at AX5")
        XCTAssertTrue(element(app, "paywall.purchase").isHittable, "purchase button scrolled off at AX5")
    }

    func test_selectingMonthlyMovesTheSelection() {
        let app = launchPaywall()
        let monthly = element(app, "paywall.plan.monthly")
        monthly.tap()
        XCTAssertTrue(monthly.isSelected)
        XCTAssertFalse(element(app, "paywall.plan.annual").isSelected)
    }
}
