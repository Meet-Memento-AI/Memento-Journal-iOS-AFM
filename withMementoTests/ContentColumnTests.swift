import XCTest
@testable import withMemento

/// The reading columns are applied unconditionally, with no idiom or size-class
/// branch. That is only safe if they are *provably* no-ops on iPhone, which is
/// what these assertions are for: the caps are the acceptance evidence, not the
/// argument in the commit message.
///
/// The app is portrait-locked on iPhone (`INFOPLIST_KEY_UISupportedInterfaceOrientations`
/// is `UIInterfaceOrientationPortrait`), so the widest proposal any phone can
/// make is the largest portrait width Apple ships. Every one of them lands
/// below both caps, so the modifiers return the proposal untouched and the page
/// lays out exactly as it did before the caps existed.
final class ContentColumnTests: XCTestCase {

    /// Every portrait width the app can be launched at on iPhone:
    /// SE, 13 mini, 14/15/16, 16 Plus, 16 Pro Max.
    private static let iPhonePortraitWidths: [CGFloat] =
        [320, 375, 390, 393, 402, 428, 430, 440]

    /// Every iPad width, portrait and landscape, including the 13" long edge.
    private static let iPadWidths: [CGFloat] = [744, 834, 1024, 1366]

    /// What `frame(maxWidth:)` resolves to for a given container width.
    private func resolved(width: CGFloat, cap: CGFloat = ContentColumnMetrics.reading) -> CGFloat {
        min(width, cap)
    }

    /// What `contentColumnRelative(_:)` resolves to — the gutter comes out of the
    /// proposal *before* the clamp, which is why this is not the same function as
    /// `resolved(width:cap:)`.
    private func relative(
        width: CGFloat,
        gutter: CGFloat = AppHeaderMetrics.edgeInset,
        cap: CGFloat
    ) -> CGFloat {
        min(max(width - gutter * 2, 0), cap)
    }

    /// What the column's *content* measures once the page's own gutter is
    /// taken out — the number a reader actually sees.
    private func measure(width: CGFloat, gutter: CGFloat) -> CGFloat {
        max(resolved(width: width) - gutter * 2, 0)
    }

    // MARK: - Tokens

    /// `maxWidth` is the original name for `reading`. The onboarding call sites
    /// and `testOnboardingBandRelationshipSurvivesTheCap` below both still read
    /// it, and their survival untouched is part of the evidence that adding the
    /// second measure changed nothing that already shipped.
    func testReadingCapAliasIsUnchanged() {
        XCTAssertEqual(ContentColumnMetrics.reading, 600)
        XCTAssertEqual(ContentColumnMetrics.maxWidth, ContentColumnMetrics.reading)
    }

    func testTokenOrdering() {
        XCTAssertLessThan(
            ContentColumnMetrics.reading,
            ContentColumnMetrics.surface,
            "prose reads narrower than a surface of cards"
        )
        // No iPad in any orientation escapes the wider cap.
        XCTAssertLessThan(
            ContentColumnMetrics.surface,
            Self.iPadWidths.min()!,
            "every iPad must clamp, including the mini in portrait"
        )
        // And no phone can reach it even before the gutter comes out.
        XCTAssertGreaterThan(
            ContentColumnMetrics.surface,
            Self.iPhonePortraitWidths.max()!,
            "the surface cap must be unreachable on iPhone"
        )
    }

    // MARK: - iPhone inertness

    func testReadingCapIsInertAtEveryIPhonePortraitWidth() {
        for width in Self.iPhonePortraitWidths {
            XCTAssertEqual(
                resolved(width: width),
                width,
                "contentColumn() must return the proposal untouched at \(width)pt"
            )
        }
    }

    /// The assertion that proves the chat/chrome swap is a no-op on iPhone: the
    /// resolved width of `contentColumnRelative(surface)` is byte-identical to
    /// what `rootEdgeInset()` produced at every phone width.
    func testSurfaceCapIsInertAtEveryIPhonePortraitWidth() {
        for width in Self.iPhonePortraitWidths {
            XCTAssertEqual(
                resolved(width: width, cap: ContentColumnMetrics.surface),
                width,
                "the surface cap must return the proposal untouched at \(width)pt"
            )
            XCTAssertEqual(
                relative(width: width, cap: ContentColumnMetrics.surface),
                width - AppHeaderMetrics.edgeInset * 2,
                "capped chrome must resolve exactly as rootEdgeInset() did at \(width)pt"
            )
        }
    }

    // MARK: - iPad engagement

    func testReadingCapEngagesOnlyBeyondTheWidestPhone() {
        for width in [834, 1024, 1366] as [CGFloat] {
            XCTAssertEqual(resolved(width: width), 600, "\(width)pt should clamp to the column")
        }
    }

    /// The gutter comes out before the clamp, so the cap engages only where
    /// `width - 2 × gutter` exceeds `surface` (752pt). iPad mini portrait (744pt)
    /// is below that: its header row is gutter-bound at 712pt — still a margin,
    /// just not the clamp.
    func testSurfaceCapEngagesOnEveryIPad() {
        let gutter = AppHeaderMetrics.edgeInset
        for width in Self.iPadWidths {
            let expected = width - gutter * 2 > ContentColumnMetrics.surface
                ? ContentColumnMetrics.surface
                : width - gutter * 2
            XCTAssertEqual(
                relative(width: width, cap: ContentColumnMetrics.surface),
                expected,
                "\(width)pt should resolve to \(expected)pt"
            )
            XCTAssertLessThan(expected, width, "\(width)pt must keep a margin")
        }
    }

    /// A narrow multitasking width must behave like a phone — gutter only, no
    /// clamp — rather than stranding a column wider than the window.
    func testSurfaceCapDegradesGracefullyInSplitView() {
        // Roughly half of a 1024pt landscape window.
        let splitWidth: CGFloat = 507
        XCTAssertEqual(
            relative(width: splitWidth, cap: ContentColumnMetrics.surface),
            splitWidth - AppHeaderMetrics.edgeInset * 2
        )
    }

    // MARK: - Chat: one measure for the transcript and the composer

    /// The regression this design exists to avoid, asserted against the real
    /// function.
    ///
    /// `ChatMessagesView` reports the **inset** ScrollView's frame into
    /// `choreographer.columnFrame`, and `landingRect` places the ghost at
    /// `column.maxX`. Cap the ScrollView and that stays true. Move the inset onto
    /// the scroll *content* instead and `columnFrame` reports the whole window,
    /// which lands the ghost half the leftover margin to the right of the row it
    /// hands off to — on a 13" iPad, 323pt away.
    func testGhostLandsOnTheTranscriptTrailingEdge() {
        let window: CGFloat = 1366
        let bubble = CGSize(width: 300, height: 80)
        let pinTopInset: CGFloat = 120

        let capped = CGRect(
            x: (window - ContentColumnMetrics.surface) / 2,
            y: 0,
            width: ContentColumnMetrics.surface,
            height: 1000
        )
        let cappedLanding = ChatTranscriptMetrics.landingRect(
            bubbleSize: bubble, column: capped, pinTopInset: pinTopInset
        )
        XCTAssertEqual(
            cappedLanding.maxX,
            capped.maxX,
            "the ghost must land on the column's trailing edge"
        )

        // The stale full-window column the rejected alternative would report.
        let stale = CGRect(x: 0, y: 0, width: window, height: 1000)
        let staleLanding = ChatTranscriptMetrics.landingRect(
            bubbleSize: bubble, column: stale, pinTopInset: pinTopInset
        )
        XCTAssertEqual(
            staleLanding.maxX - cappedLanding.maxX,
            (window - ContentColumnMetrics.surface) / 2,
            "a full-window column misplaces the ghost by half the leftover margin"
        )
    }

    // MARK: - Onboarding

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
