import XCTest
import SwiftUI
@testable import MeetMemento

/// Covers the layout arithmetic behind Chat's pinned send choreography.
///
/// The state machine lives in `ChatSendChoreographerTests` below; this half is
/// the maths, which is where a regression would be silent — a wrong reserve
/// looks like "the scroll is slightly off" rather than a crash.
final class ChatTranscriptMetricsTests: XCTestCase {

    // MARK: - reserve

    func test_reserve_emptyTurn_fillsTheViewport() {
        XCTAssertEqual(ChatTranscriptMetrics.reserve(viewportHeight: 800, activeTurnHeight: 0), 800)
    }

    func test_reserve_turnShorterThanViewport_fillsTheRemainder() {
        XCTAssertEqual(ChatTranscriptMetrics.reserve(viewportHeight: 800, activeTurnHeight: 300), 500)
    }

    func test_reserve_turnExactlyOneViewport_isZero() {
        XCTAssertEqual(ChatTranscriptMetrics.reserve(viewportHeight: 800, activeTurnHeight: 800), 0)
    }

    func test_reserve_turnExceedingViewport_isZeroNotNegative() {
        XCTAssertEqual(ChatTranscriptMetrics.reserve(viewportHeight: 800, activeTurnHeight: 2400), 0)
    }

    func test_reserve_neverNegative_forDegenerateInputs() {
        XCTAssertEqual(ChatTranscriptMetrics.reserve(viewportHeight: 0, activeTurnHeight: 0), 0)
        XCTAssertEqual(ChatTranscriptMetrics.reserve(viewportHeight: -10, activeTurnHeight: 0), 0)
        XCTAssertEqual(ChatTranscriptMetrics.reserve(viewportHeight: 800, activeTurnHeight: -50), 800)
    }

    // MARK: - The invariant

    /// The property the entire feature rests on.
    ///
    /// While the turn is shorter than the viewport, the maximum scroll offset
    /// must equal the pin offset *exactly* — independent of both how much has
    /// streamed in and how tall the viewport currently is.
    ///
    /// Independence from `activeTurnHeight` is what makes the pin static during
    /// streaming; independence from `viewportHeight` is what makes it immune to
    /// the keyboard. If the reserve is ever measured against the wrong span —
    /// the 32pt row-spacing bug, say — this is the test that fails.
    func test_maxScrollOffset_equalsPinOffset_regardlessOfTurnHeightOrViewport() {
        let pinOffset: CGFloat = 1234

        for viewport in stride(from: CGFloat(200), through: 1200, by: 100) {
            for turn in stride(from: CGFloat(0), through: viewport, by: 25) {
                let reserve = ChatTranscriptMetrics.reserve(
                    viewportHeight: viewport, activeTurnHeight: turn
                )
                let contentHeight = pinOffset + turn + reserve
                let maxScrollOffset = contentHeight - viewport

                XCTAssertEqual(
                    maxScrollOffset, pinOffset, accuracy: 0.0001,
                    "viewport \(viewport), turn \(turn): pin must be exactly the scroll limit"
                )
            }
        }
    }

    /// Once the turn outgrows the viewport the reserve is spent, and the pinned
    /// message is free to scroll up off the top — the ChatGPT behaviour.
    func test_maxScrollOffset_exceedsPin_onceTurnOutgrowsViewport() {
        let pinOffset: CGFloat = 500
        let viewport: CGFloat = 800
        let turn: CGFloat = 2000

        let reserve = ChatTranscriptMetrics.reserve(viewportHeight: viewport, activeTurnHeight: turn)
        XCTAssertEqual(reserve, 0)

        let maxScrollOffset = (pinOffset + turn + reserve) - viewport
        XCTAssertGreaterThan(maxScrollOffset, pinOffset)
    }

    // MARK: - optimisticReserve

    /// The over-reserve must never be *smaller* than the settled one, or the
    /// scroll issued against it would clamp short of the pin and the flying
    /// bubble would land on empty space.
    func test_optimisticReserve_isNeverSmallerThanTheSettledReserve() {
        for viewport in stride(from: CGFloat(0), through: 1200, by: 50) {
            for turn in stride(from: CGFloat(0), through: 2000, by: 50) {
                XCTAssertGreaterThanOrEqual(
                    ChatTranscriptMetrics.optimisticReserve(viewportHeight: viewport),
                    ChatTranscriptMetrics.reserve(viewportHeight: viewport, activeTurnHeight: turn),
                    "viewport \(viewport), turn \(turn)"
                )
            }
        }
    }

    /// Over-reserving keeps the pin reachable — it only adds slack below it.
    func test_optimisticReserve_keepsPinReachable() {
        let pinOffset: CGFloat = 400
        let viewport: CGFloat = 800
        let turn: CGFloat = 120

        let optimistic = ChatTranscriptMetrics.optimisticReserve(viewportHeight: viewport)
        let maxScrollOffset = (pinOffset + turn + optimistic) - viewport

        XCTAssertGreaterThanOrEqual(maxScrollOffset, pinOffset)
    }

    func test_optimisticReserve_neverNegative() {
        XCTAssertEqual(ChatTranscriptMetrics.optimisticReserve(viewportHeight: -200), 0)
    }

    // MARK: - activeTurnHeight

    func test_activeTurnHeight_isZeroWithNoPinnedRow() {
        XCTAssertEqual(
            ChatTranscriptMetrics.activeTurnHeight(lastUserTopY: nil, transcriptEndY: 900), 0
        )
    }

    func test_activeTurnHeight_spansPinnedRowToTranscriptEnd() {
        XCTAssertEqual(
            ChatTranscriptMetrics.activeTurnHeight(lastUserTopY: 200, transcriptEndY: 950), 750
        )
    }

    /// Reporters can land out of order for a frame; a negative span must not
    /// leak into the reserve as an inflated value.
    func test_activeTurnHeight_clampsInvertedReports() {
        XCTAssertEqual(
            ChatTranscriptMetrics.activeTurnHeight(lastUserTopY: 900, transcriptEndY: 200), 0
        )
    }

    // MARK: - The clamp this feature exists to avoid

    /// The bug, stated as arithmetic.
    ///
    /// In the update that appends a message the transcript is still laid out
    /// with the *previous* turn's reserve. Once a real reply exists that reserve
    /// is 0, so the pin sits a whole viewport minus the new turn outside the
    /// scroll range — and `scrollTo` clamps there instead of failing, landing
    /// the transcript short while the ghost flies to the real pin regardless.
    func test_pinIsUnreachable_inTheLayoutTheSendTurnLeavesBehind() {
        let viewport: CGFloat = 800
        let pinOffset: CGFloat = 1400
        let previousTurn: CGFloat = 900
        let newTurn: CGFloat = 180

        let staleReserve = ChatTranscriptMetrics.reserve(
            viewportHeight: viewport, activeTurnHeight: previousTurn
        )
        XCTAssertEqual(staleReserve, 0, "a turn taller than the viewport leaves no reserve")

        XCTAssertFalse(
            ChatTranscriptMetrics.pinIsReachable(
                pinOffset: pinOffset,
                contentHeight: pinOffset + newTurn + staleReserve,
                viewportHeight: viewport
            ),
            "the pin must be recognised as out of range in the stale layout"
        )
    }

    func test_pinIsReachable_onceTheReserveIsSizedForTheNewTurn() {
        let viewport: CGFloat = 800
        let pinOffset: CGFloat = 1400

        XCTAssertTrue(
            ChatTranscriptMetrics.pinIsReachable(
                pinOffset: pinOffset,
                contentHeight: pinOffset + viewport,
                viewportHeight: viewport
            )
        )
    }

    func test_pinIsReachable_atExactlyTheLimit() {
        XCTAssertTrue(
            ChatTranscriptMetrics.pinIsReachable(
                pinOffset: 500, contentHeight: 1300, viewportHeight: 800
            ),
            "maxScrollOffset == pinOffset is the designed resting state, not a miss"
        )
    }

    // MARK: - Validity-gated reserve

    /// A measurement belonging to the previous row must never shrink the
    /// reserve: spanning two turns makes `activeTurnHeight` far too large.
    func test_reserve_ignoresAMeasurementFromThePreviousRow() {
        let previous = PinnedRowTop(id: UUID(), y: 100)

        XCTAssertEqual(
            ChatTranscriptMetrics.reserve(
                viewportHeight: 800,
                pinnedRowID: UUID(),
                measurement: previous,
                transcriptEndY: 1400
            ),
            800,
            "a stale measurement must fall back to the full-viewport reserve"
        )
    }

    func test_reserve_usesAMatchingMeasurement() {
        let id = UUID()

        XCTAssertEqual(
            ChatTranscriptMetrics.reserve(
                viewportHeight: 800,
                pinnedRowID: id,
                measurement: PinnedRowTop(id: id, y: 1220),
                transcriptEndY: 1400
            ),
            620,
            "800 viewport minus a 180pt turn"
        )
    }

    func test_reserve_fallsBackWithNoMeasurementOrNoPinnedRow() {
        let id = UUID()

        XCTAssertEqual(
            ChatTranscriptMetrics.reserve(
                viewportHeight: 800, pinnedRowID: id, measurement: nil, transcriptEndY: 1400
            ),
            800
        )
        XCTAssertEqual(
            ChatTranscriptMetrics.reserve(
                viewportHeight: 800,
                pinnedRowID: nil,
                measurement: PinnedRowTop(id: id, y: 1220),
                transcriptEndY: 1400
            ),
            800,
            "an empty transcript has nothing to pin, so it reserves conservatively"
        )
    }

    // MARK: - pinDelta

    func test_pinDelta_isZeroWhenTheRowSitsOnThePin() {
        XCTAssertEqual(
            ChatTranscriptMetrics.pinDelta(
                rowTopInContent: 1400, contentOffsetY: 1400 - 155, contentInsetTop: 155
            ),
            0
        )
    }

    /// The signature of a clamped scroll: the row is still below the pin.
    func test_pinDelta_isPositiveWhenTheScrollClampedShort() {
        XCTAssertEqual(
            ChatTranscriptMetrics.pinDelta(
                rowTopInContent: 1400, contentOffsetY: 800, contentInsetTop: 155
            ),
            445,
            "matches the shortfall the failing UI test measured"
        )
    }

    /// The signature of content shrinking under a landed pin — the loading row
    /// leaving at stream end, or the keyboard falling.
    func test_pinDelta_isNegativeWhenTheRowHasBeenPushedAboveThePin() {
        XCTAssertLessThan(
            ChatTranscriptMetrics.pinDelta(
                rowTopInContent: 1400, contentOffsetY: 1300, contentInsetTop: 155
            ),
            0
        )
    }

    // MARK: - landingRect

    // MARK: - Bubble width parity

    /// The ghost and the real row must wrap at the SAME width, or the ghost
    /// renders a different number of lines than the row it hands off to and the
    /// text visibly reflows at the handoff.
    func test_maxWidth_accountsForBothTheGutterAndTheRowSpacing() {
        let column: CGFloat = 361

        XCTAssertEqual(
            UserBubbleSurface.maxWidth(inColumnWidth: column),
            column - UserBubbleSurface.leadingGutter - UserBubbleSurface.rowSpacing,
            "omitting the HStack spacing made the ghost 12pt wider than the row"
        )
        XCTAssertEqual(UserBubbleSurface.maxWidth(inColumnWidth: column), 289)
    }

    func test_maxWidth_neverNegative() {
        XCTAssertEqual(UserBubbleSurface.maxWidth(inColumnWidth: 10), 0)
    }

    // MARK: - Beat 1 destination

    /// Beat 1 flies to where the row actually landed, which is the pin offset by
    /// however far this send still has to scroll. That offset is what makes the
    /// motion adapt to the conversation's length.
    func test_beatOneDestination_isThePinOffsetByTheRemainingScroll() {
        let column = CGRect(x: 16, y: 0, width: 361, height: 800)
        let size = CGSize(width: 240, height: 96)
        let pin = ChatTranscriptMetrics.landingRect(
            bubbleSize: size, column: column, pinTopInset: 155
        )

        // Empty chat: nothing left to scroll, so beat 1 goes straight to the pin.
        XCTAssertEqual(pin.offsetBy(dx: 0, dy: 0), pin)

        // Long thread: the row landed 420pt below the pin, so beat 1 stops there
        // and beat 2 covers the rest.
        XCTAssertEqual(pin.offsetBy(dx: 0, dy: 420).minY, pin.minY + 420)
        XCTAssertEqual(pin.offsetBy(dx: 0, dy: 420).size, size, "only the position moves")
    }

    /// The offset beat 1 uses and the distance beat 2 travels are the same
    /// number, derived from the same function the pin correction uses.
    func test_beatOneOffset_andBeatTwoDistance_areTheSameQuantity() {
        let rowTop: CGFloat = 1400
        let offsetY: CGFloat = 800
        let insetTop: CGFloat = 155

        let delta = ChatTranscriptMetrics.pinDelta(
            rowTopInContent: rowTop, contentOffsetY: offsetY, contentInsetTop: insetTop
        )
        XCTAssertEqual(delta, 445)

        // Applying it to the pin puts the ghost exactly where the row sits, so
        // the handoff is a no-op rather than a jump.
        let column = CGRect(x: 16, y: 0, width: 361, height: 800)
        let pin = ChatTranscriptMetrics.landingRect(
            bubbleSize: CGSize(width: 240, height: 96), column: column, pinTopInset: insetTop
        )
        XCTAssertEqual(pin.offsetBy(dx: 0, dy: delta).minY, insetTop + delta)
    }

    // MARK: - Beat 2 duration

    func test_sendScrollDuration_clampsAtBothEnds() {
        XCTAssertEqual(Motion.sendScrollDuration(distance: 0), 0.25, accuracy: 0.0001)
        XCTAssertEqual(Motion.sendScrollDuration(distance: 700), 0.50, accuracy: 0.0001)
        XCTAssertEqual(
            Motion.sendScrollDuration(distance: 5000), 0.50, accuracy: 0.0001,
            "beyond a viewport the duration must stop growing"
        )
    }

    func test_sendScrollDuration_ignoresDirection() {
        XCTAssertEqual(
            Motion.sendScrollDuration(distance: -400),
            Motion.sendScrollDuration(distance: 400),
            accuracy: 0.0001
        )
    }

    func test_sendScrollDuration_isMonotonicInDistance() {
        var previous = Motion.sendScrollDuration(distance: 0)
        for distance in stride(from: CGFloat(25), through: 1400, by: 25) {
            let next = Motion.sendScrollDuration(distance: distance)
            XCTAssertGreaterThanOrEqual(next, previous, "distance \(distance)")
            previous = next
        }
    }

    /// The window `.settling` holds the offset for must STRICTLY exceed the
    /// animation it covers. If it did not, the corrective pass would be re-armed
    /// on beat 2's last frames and the final few points would visibly snap —
    /// the "there is no scroll, it just jumps" bug in miniature.
    func test_sendScrollSettleWindow_alwaysOutlastsTheAnimation() {
        for distance in stride(from: CGFloat(0), through: 1400, by: 25) {
            XCTAssertGreaterThan(
                Motion.sendScrollSettleWindow(distance: distance),
                Motion.sendScrollDuration(distance: distance),
                "distance \(distance)"
            )
        }
    }

    /// `.settling` suppresses every pin correction, so a stranded settle must
    /// not be able to survive into the reply.
    func test_sendScrollSettleWindow_isBounded() {
        XCTAssertLessThan(Motion.sendScrollSettleWindow(distance: 100_000), 0.6)
    }

    func test_landingRect_isTrailingAlignedAtThePin() {
        let column = CGRect(x: 16, y: 0, width: 360, height: 800)
        let rect = ChatTranscriptMetrics.landingRect(
            bubbleSize: CGSize(width: 240, height: 88),
            column: column,
            pinTopInset: 155
        )

        XCTAssertEqual(rect.maxX, column.maxX, "bubble hugs the trailing edge")
        XCTAssertEqual(rect.minY, 155, "top edge sits on the pin")
        XCTAssertEqual(rect.size, CGSize(width: 240, height: 88))
    }

    func test_landingRect_offsetsByTheColumnOrigin() {
        let column = CGRect(x: 16, y: 40, width: 360, height: 800)
        let rect = ChatTranscriptMetrics.landingRect(
            bubbleSize: CGSize(width: 100, height: 50),
            column: column,
            pinTopInset: 155
        )

        XCTAssertEqual(rect.minY, 195, "the pin is relative to the column, not the screen")
    }
}

// MARK: - State machine

@MainActor
final class ChatSendChoreographerTests: XCTestCase {

    private let composer = CGRect(x: 16, y: 700, width: 360, height: 64)
    private let column = CGRect(x: 16, y: 0, width: 360, height: 800)

    private func makeReady() -> ChatSendChoreographer {
        let sut = ChatSendChoreographer()
        sut.composerFrame = composer
        sut.columnFrame = column
        sut.captureOrigin()
        return sut
    }

    func test_begin_withEverythingAvailable_flies() {
        let sut = makeReady()
        let id = UUID()

        sut.begin(messageID: id, text: "hello", wantsFlight: true, reduceMotion: false)

        XCTAssertEqual(sut.phase, .preparing(messageID: id))
        XCTAssertEqual(sut.flight?.id, id)
        XCTAssertEqual(sut.flight?.origin, composer)
        XCTAssertEqual(sut.hiddenMessageID, id, "the real row must be hidden behind the ghost")
    }

    func test_begin_withoutFlight_pinsInstantly() {
        let sut = makeReady()
        let id = UUID()

        sut.begin(messageID: id, text: "hello", wantsFlight: false, reduceMotion: false)

        XCTAssertEqual(sut.phase, .pinned(messageID: id))
        XCTAssertNil(sut.flight)
        XCTAssertNil(sut.hiddenMessageID, "nothing is standing in, so nothing may be hidden")
    }

    func test_begin_underReduceMotion_pinsInstantly() {
        let sut = makeReady()
        let id = UUID()

        sut.begin(messageID: id, text: "hello", wantsFlight: true, reduceMotion: true)

        XCTAssertEqual(sut.phase, .pinned(messageID: id))
        XCTAssertNil(sut.flight)
    }

    func test_begin_withoutAComposerFrame_pinsInstantly() {
        let sut = ChatSendChoreographer()
        sut.columnFrame = column   // no composerFrame, so no origin to capture
        sut.captureOrigin()
        let id = UUID()

        sut.begin(messageID: id, text: "hello", wantsFlight: true, reduceMotion: false)

        XCTAssertEqual(sut.phase, .pinned(messageID: id))
        XCTAssertNil(sut.flight)
    }

    func test_begin_withoutAColumnFrame_pinsInstantly() {
        let sut = ChatSendChoreographer()
        sut.composerFrame = composer
        sut.captureOrigin()
        let id = UUID()

        sut.begin(messageID: id, text: "hello", wantsFlight: true, reduceMotion: false)

        XCTAssertEqual(sut.phase, .pinned(messageID: id))
    }

    func test_landRevealsTheRow() {
        let sut = makeReady()
        let id = UUID()
        sut.begin(messageID: id, text: "hello", wantsFlight: true, reduceMotion: false)
        sut.markFlying(messageID: id)
        XCTAssertTrue(sut.isFlying)

        sut.land(messageID: id)

        XCTAssertEqual(sut.phase, .pinned(messageID: id))
        XCTAssertNil(sut.flight)
        XCTAssertNil(sut.hiddenMessageID)
    }

    /// A late watchdog from a previous turn must not tear down the current one.
    func test_land_withAStaleID_isIgnored() {
        let sut = makeReady()
        let id = UUID()
        sut.begin(messageID: id, text: "hello", wantsFlight: true, reduceMotion: false)

        sut.land(messageID: UUID())

        XCTAssertEqual(sut.phase, .preparing(messageID: id))
        XCTAssertNotNil(sut.flight)
    }

    func test_markFlying_withAStaleID_isIgnored() {
        let sut = makeReady()
        let id = UUID()
        sut.begin(messageID: id, text: "hello", wantsFlight: true, reduceMotion: false)

        sut.markFlying(messageID: UUID())

        XCTAssertEqual(sut.phase, .preparing(messageID: id))
    }

    func test_release_onlyAppliesOncePinned() {
        let sut = makeReady()
        let id = UUID()
        sut.begin(messageID: id, text: "hello", wantsFlight: true, reduceMotion: false)
        sut.markFlying(messageID: id)

        sut.release()
        XCTAssertEqual(sut.phase, .flying(messageID: id), "a scroll mid-flight must not release")

        sut.land(messageID: id)
        sut.release()
        XCTAssertEqual(sut.phase, .released)
    }

    func test_captureOriginIsConsumedBySingleFlight() {
        let sut = makeReady()
        let first = UUID()
        sut.begin(messageID: first, text: "one", wantsFlight: true, reduceMotion: false)
        sut.land(messageID: first)

        // No second captureOrigin() — the next send must not reuse the old one.
        let second = UUID()
        sut.begin(messageID: second, text: "two", wantsFlight: true, reduceMotion: false)

        XCTAssertEqual(sut.phase, .pinned(messageID: second))
        XCTAssertNil(sut.flight)
    }

    func test_reset_clearsEverything() {
        let sut = makeReady()
        let id = UUID()
        sut.begin(messageID: id, text: "hello", wantsFlight: true, reduceMotion: false)

        sut.reset()

        XCTAssertEqual(sut.phase, .idle)
        XCTAssertNil(sut.flight)
        XCTAssertNil(sut.hiddenMessageID)
    }

    func test_hiddenMessageID_isNilInEveryRestingPhase() {
        let sut = ChatSendChoreographer()
        XCTAssertNil(sut.hiddenMessageID, "idle")

        sut.composerFrame = composer
        sut.columnFrame = column
        sut.captureOrigin()
        let id = UUID()
        sut.begin(messageID: id, text: "hello", wantsFlight: true, reduceMotion: false)
        sut.land(messageID: id)
        XCTAssertNil(sut.hiddenMessageID, "pinned")

        sut.release()
        XCTAssertNil(sut.hiddenMessageID, "released")
    }
}
