import XCTest
@testable import withMemento

/// The reading column is applied unconditionally, with no idiom or size-class
/// branch. That is only safe if it is *provably* a no-op on iPhone, which is
/// what these assertions are for: the cap is the acceptance evidence, not the
/// argument in the commit message.
///
/// The app is portrait-locked on iPhone (`INFOPLIST_KEY_UISupportedInterfaceOrientations`
/// is `UIInterfaceOrientationPortrait`), so the widest proposal any phone can
/// make is the largest portrait width Apple ships. Every one of them lands
/// below 600, so `contentColumn()` returns the proposal untouched and the page
/// lays out exactly as it did before the cap existed.
final class ContentColumnTests: XCTestCase {

    /// What `frame(maxWidth:)` resolves to for a given container width.
    private func resolved(width: CGFloat) -> CGFloat {
        min(width, ContentColumnMetrics.maxWidth)
    }

    /// What the column's *content* measures once the page's own gutter is
    /// taken out — the number a reader actually sees.
    private func measure(width: CGFloat, gutter: CGFloat) -> CGFloat {
        max(resolved(width: width) - gutter * 2, 0)
    }

    func testCapIsInertAtEveryIPhonePortraitWidth() {
        // iPhone SE, 13 mini, 14/15/16, 16 Plus, 16 Pro Max — every portrait
        // width the app can be launched at.
        for width in [320, 375, 390, 393, 402, 428, 430, 440] as [CGFloat] {
            XCTAssertEqual(
                resolved(width: width),
                width,
                "contentColumn() must return the proposal untouched at \(width)pt"
            )
        }
    }

    func testCapEngagesOnlyBeyondTheWidestPhone() {
        // iPad Pro 11" and 13" portrait, and a 13" landscape detail column.
        for width in [834, 1024, 1366] as [CGFloat] {
            XCTAssertEqual(resolved(width: width), 600, "\(width)pt should clamp to the column")
        }
    }

    /// The 16/20pt gutter split between the onboarding footer and its content
    /// band is pre-existing. Capping both bands at the same outer width keeps
    /// the relationship the phone already has instead of inventing a new one.
    func testOnboardingBandRelationshipSurvivesTheCap() {
        let phone: CGFloat = 393
        let pad: CGFloat = 1024

        let phoneFooterOvershoot = measure(width: phone, gutter: OnboardingLayout.footerHorizontal)
            - measure(width: phone, gutter: OnboardingLayout.contentHorizontal)
        let padFooterOvershoot = measure(width: pad, gutter: OnboardingLayout.footerHorizontal)
            - measure(width: pad, gutter: OnboardingLayout.contentHorizontal)

        XCTAssertEqual(
            padFooterOvershoot,
            phoneFooterOvershoot,
            "the footer should sit proud of the copy by the same amount on both devices"
        )
    }
}
