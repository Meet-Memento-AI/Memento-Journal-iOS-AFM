import SwiftUI
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

    // MARK: - Regular width: one column, one inset

    /// `rootEdgeInset()` is how header rows, the Chat transcript and composer,
    /// and the editor chrome take their width. On every phone it must still
    /// be the full width less the 16pt gutter it always was.
    func testRootEdgeInsetIsUnchangedAtEveryIPhonePortraitWidth() {
        for width in [320, 375, 390, 393, 402, 428, 430, 440] as [CGFloat] {
            XCTAssertEqual(
                ContentColumnMetrics.insetWidth(in: width),
                width - AppHeaderMetrics.edgeInset * 2,
                "rootEdgeInset() must not move at \(width)pt"
            )
        }
    }

    /// The safe-area column (pushed Settings/Insights pages, sheets) adds no
    /// padding at any phone width.
    func testSafeAreaColumnIsInertAtEveryIPhonePortraitWidth() {
        for width in [320, 375, 390, 393, 402, 428, 430, 440] as [CGFloat] {
            XCTAssertEqual(ContentColumnMetrics.sideInset(in: width), 0, "\(width)pt")
        }
    }

    /// iPad 11" and 13", portrait and landscape, plus the half-screen Split
    /// View widths that stay regular. Every column-sizing path must agree on
    /// the same two edges, and the shared gutter sits inside them.
    func testEveryColumnPathSharesTheSameEdgesOnIPad() {
        for width in [683, 820, 834, 1024, 1032, 1180, 1194, 1366, 1376] as [CGFloat] {
            let column = ContentColumnMetrics.columnWidth(in: width)
            XCTAssertEqual(column, 600, "\(width)pt should clamp to the column")
            XCTAssertEqual(
                width - ContentColumnMetrics.sideInset(in: width) * 2,
                column,
                "safe-area column and frame column must match at \(width)pt"
            )
            XCTAssertEqual(
                ContentColumnMetrics.insetWidth(in: width) + AppHeaderMetrics.edgeInset * 2,
                column,
                "rootEdgeInset() must sit one gutter inside the column at \(width)pt"
            )
        }
    }

    /// Slide Over and narrow Split View drop to compact width. The column must
    /// hand the page back untouched there, exactly like a phone.
    func testNarrowIPadSplitWidthsFallBackToThePhoneLayout() {
        for width in [320, 375, 438, 507, 551] as [CGFloat] {
            XCTAssertEqual(ContentColumnMetrics.columnWidth(in: width), width)
            XCTAssertEqual(ContentColumnMetrics.sideInset(in: width), 0)
            XCTAssertEqual(
                ContentColumnMetrics.insetWidth(in: width),
                width - AppHeaderMetrics.edgeInset * 2
            )
        }
    }

    // MARK: - Regular width: native header

    /// `AppHeader` only hands its controls to a toolbar inside a page that
    /// `rootNavigationStack(title:)` actually wrapped. Anywhere else, including
    /// every compact-width page, the glass row stays.
    func testHeaderStaysAGlassRowUnlessANavigationBarHostsIt() {
        XCTAssertFalse(EnvironmentValues().rootNavigationBarHosted)
    }

    func testEveryVisibleRootPageHasANavigationTitle() {
        XCTAssertEqual(RootPage.journal.navigationTitle, "Journal")
        XCTAssertEqual(RootPage.chat.navigationTitle, "Chat")
        for page in RootPage.visibleCases {
            XCTAssertFalse(page.navigationTitle.isEmpty, "\(page)")
        }
    }

    // MARK: - Regular width: top spacing under the bar

    /// Compact pages clear the floating glass row by hand; these must be the
    /// exact values iPhone has always used.
    func testCompactTopSpacingIsThePhoneHeaderClearance() {
        XCTAssertEqual(
            RootContentInsets.contentTopPadding(hosted: false),
            AppHeaderMetrics.contentTopPadding
        )
        XCTAssertEqual(
            RootContentInsets.chatPinTopInset(hosted: false),
            AppHeaderMetrics.chatPinTopInset
        )
    }

    /// Under a native bar the safe area already clears the bar, so content
    /// gets only the standard gap below it — the same 16pt the glass row gets
    /// — and none of the glass row's own clearance on top.
    func testHostedTopSpacingIsTheStandardGapBelowTheBar() {
        XCTAssertEqual(RootContentInsets.contentTopPadding(hosted: true), AppHeaderMetrics.contentGap)
        XCTAssertEqual(RootContentInsets.contentTopPadding(hosted: true), 16)
        XCTAssertEqual(RootContentInsets.chatPinTopInset(hosted: true), AppHeaderMetrics.chatPinGap)
        XCTAssertEqual(
            RootContentInsets.contentTopPadding(hosted: false)
                - RootContentInsets.contentTopPadding(hosted: true),
            AppHeaderMetrics.headerClearance,
            "hosted content must drop exactly the glass row's clearance"
        )
    }
}
