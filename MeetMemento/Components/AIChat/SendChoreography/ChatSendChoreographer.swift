//
//  ChatSendChoreographer.swift
//  MeetMemento
//
//  Send choreography for Chat: the user's bubble flies from the composer to a
//  pinned rest position 32pt below the header, and holds there while the reply
//  streams in underneath.
//

import SwiftUI
import UIKit

// MARK: - Coordinate spaces

/// Two named spaces, and the split is a performance requirement rather than a
/// style preference.
enum ChatSpace {
    /// Outermost space on `AIChatView`. The composer capsule, the transcript
    /// column, and the flight overlay all resolve into this one so their rects
    /// are directly comparable.
    static let page = "chat.page"

    /// The scroll view's *content* space. Scroll-invariant, so geometry
    /// reporters attached inside it fire on real layout changes only. The same
    /// reporters in `.global` would fire on every scroll frame and thrash
    /// `@State` for the entire length of a reply.
    static let content = "chat.content"
}

// MARK: - Measurements

/// The top of the pinned row, tagged with the row it was measured from.
///
/// The tag is the whole point. Untagged, a measurement of the *previous* turn's
/// row is indistinguishable from one of the current row — and feeding it to
/// `activeTurnHeight` spans two turns instead of one, which makes the reserve
/// far too small, puts the pin outside the scroll range, and clamps.
struct PinnedRowTop: Equatable {
    let id: UUID
    let y: CGFloat
}

// MARK: - Layout maths

/// Pure layout arithmetic for the pinned transcript. No SwiftUI, no state, so
/// the invariant the whole feature rests on can be asserted in a unit test.
enum ChatTranscriptMetrics {

    /// Scrollable slack below the transcript so the newest user message can
    /// always reach the pin — even when it is the only short message in the
    /// thread, which is the case that fails outright without it.
    ///
    /// INVARIANT. With `reserve = viewport − activeTurnHeight`:
    ///
    ///     contentHeight   = pinOffset + activeTurnHeight + reserve
    ///                     = pinOffset + viewport
    ///     maxScrollOffset = contentHeight − viewport
    ///                     = pinOffset
    ///
    /// The pin is therefore *exactly* the bottom of the scroll range: no slack,
    /// and nothing to clamp. Two consequences the rest of this feature leans on:
    ///
    /// 1. `maxScrollOffset` carries no `viewport` term, so the keyboard rising
    ///    or falling cannot move the pinned bubble.
    /// 2. Streaming grows `activeTurnHeight` and shrinks `reserve` by the same
    ///    amount, so `contentHeight` is constant and the pin is *static* — it is
    ///    never re-asserted, which is why one frame of measurement lag is
    ///    invisible rather than a visible jump.
    static func reserve(viewportHeight: CGFloat, activeTurnHeight: CGFloat) -> CGFloat {
        max(0, viewportHeight - max(0, activeTurnHeight))
    }

    /// The reserve to use when nothing trustworthy has been measured yet.
    ///
    /// Deliberately the whole viewport. Over-reserving is provably safe —
    /// `maxScrollOffset = pinOffset + activeTurnHeight ≥ pinOffset`, so the pin
    /// stays reachable, it merely gains slack below it. Under-reserving is not:
    /// it puts the pin outside the scroll range, and a scroll past the range
    /// does not fail, it clamps, landing short and silently.
    static func optimisticReserve(viewportHeight: CGFloat) -> CGFloat {
        max(0, viewportHeight)
    }

    /// Height of the turn currently being pinned: the top of the last user
    /// message through the end of the transcript, measured in `ChatSpace.content`.
    static func activeTurnHeight(lastUserTopY: CGFloat?, transcriptEndY: CGFloat) -> CGFloat {
        guard let lastUserTopY else { return 0 }
        return max(0, transcriptEndY - lastUserTopY)
    }

    /// The reserve to apply *right now*, given what has actually been measured.
    ///
    /// Conservative by construction: with no trustworthy measurement for the row
    /// being pinned — the frames between the append and its first layout, a
    /// freshly loaded session, a row the `LazyVStack` has not materialised — this
    /// returns the full-viewport reserve rather than a number derived from the
    /// previous turn's row, which would span two turns and come out far too
    /// small. There is no wall clock here: validity decides, not elapsed time.
    static func reserve(
        viewportHeight: CGFloat,
        pinnedRowID: UUID?,
        measurement: PinnedRowTop?,
        transcriptEndY: CGFloat
    ) -> CGFloat {
        guard let pinnedRowID, let measurement, measurement.id == pinnedRowID else {
            return optimisticReserve(viewportHeight: viewportHeight)
        }
        return reserve(
            viewportHeight: viewportHeight,
            activeTurnHeight: activeTurnHeight(
                lastUserTopY: measurement.y,
                transcriptEndY: transcriptEndY
            )
        )
    }

    /// How far the pinned row sits below the pin, in points. Zero is landed;
    /// positive means the scroll came up short and the row is still that far
    /// down the screen.
    ///
    /// `contentOffsetY + contentInsetTop` is the content coordinate at the top
    /// of the *visible* rect — which is both what `anchor: .top` aligns to and,
    /// because the top inset IS the pin inset, exactly where the pin sits.
    static func pinDelta(
        rowTopInContent: CGFloat,
        contentOffsetY: CGFloat,
        contentInsetTop: CGFloat
    ) -> CGFloat {
        rowTopInContent - (contentOffsetY + contentInsetTop)
    }

    /// Whether the transcript *as currently laid out* can put the pinned row on
    /// the pin at all.
    ///
    /// This is the gate the send choreography waits on. In the update that
    /// appends a message the transcript is still laid out with the previous
    /// turn's reserve, and against that layout the pin is a whole viewport out
    /// of range — scrolling to it then clamps rather than failing, which is
    /// silent and looks like the bubble snapping back down.
    static func pinIsReachable(
        pinOffset: CGFloat,
        contentHeight: CGFloat,
        viewportHeight: CGFloat,
        tolerance: CGFloat = 0.5
    ) -> Bool {
        (contentHeight - viewportHeight) >= pinOffset - tolerance
    }

    /// Where the ghost comes to rest, in `ChatSpace.page`.
    ///
    /// Analytic, not measured. The pin is a *fixed point on screen*, so the
    /// landing frame is known before the destination row has laid out — and it
    /// does not move while the scroll settles underneath. That is what removes
    /// every ordering hazard `matchedGeometryEffect` would have introduced here.
    static func landingRect(bubbleSize: CGSize, column: CGRect, pinTopInset: CGFloat) -> CGRect {
        CGRect(
            x: column.maxX - bubbleSize.width,
            y: column.minY + pinTopInset,
            width: bubbleSize.width,
            height: bubbleSize.height
        )
    }
}

// MARK: - State machine

@MainActor
final class ChatSendChoreographer: ObservableObject {

    enum Phase: Equatable {
        case idle
        /// Row inserted at opacity 0, reserve widened, scroll snapped to the pin.
        case preparing(messageID: UUID)
        /// Ghost travelling composer → pin. The real row is still hidden.
        case flying(messageID: UUID)
        /// Ghost gone, row visible. The pin is held by the reserve, not by us.
        case pinned(messageID: UUID)
        /// The user took the scroll view over. Assert nothing.
        case released
    }

    struct Flight: Equatable, Identifiable {
        let id: UUID          // == the user message's id
        let text: String
        let origin: CGRect    // composer capsule, in ChatSpace.page
        let column: CGRect    // transcript column, in ChatSpace.page

        /// How far below the pin the row currently sits, in points — i.e. beat
        /// 1's destination, expressed as an offset from the pin.
        ///
        /// Deliberately optional and filled in later. At send time the row has
        /// not been laid out, so where it *lands* is not yet knowable; the
        /// ghost mounts at the composer and holds there until the transcript
        /// reports it. Nil means "not ready to fly".
        var pinOffset: CGFloat?
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var flight: Flight?

    /// Composer capsule frame as of the last completed layout, in `ChatSpace.page`.
    ///
    /// A plain `var`, not `@Published`: the composer resizes as the field wraps,
    /// and republishing that would re-render the whole transcript for nothing.
    var composerFrame: CGRect?

    /// Transcript column frame in `ChatSpace.page`. Same reasoning.
    var columnFrame: CGRect?

    private var capturedOrigin: CGRect?
    private var watchdog: Task<Void, Never>?

    /// How long the ghost may stay airborne before we force the handoff.
    private static let watchdogTimeout: Duration = .milliseconds(1200)

    /// The row that must render at opacity 0 because the ghost is standing in
    /// for it.
    ///
    /// Derived from `phase`, never assigned, so it cannot get stuck — a stuck
    /// value here would mean a message the user typed is invisible forever.
    var hiddenMessageID: UUID? {
        switch phase {
        case .preparing(let id), .flying(let id): return id
        case .idle, .pinned, .released: return nil
        }
    }

    var isFlying: Bool {
        if case .flying = phase { return true }
        return false
    }

    // MARK: Origin capture

    /// Reads the composer's pre-send geometry. Called synchronously from the
    /// composer's `onSend`, before the view model mutates anything.
    ///
    /// The ordering is load-bearing and it is guaranteed by
    /// `ChatInputField.sendMessage()`, which fires `onSend()` first and only
    /// then clears the text and collapses the field. So the frame captured here
    /// is the composer as the user last saw it, with their text still in it.
    func captureOrigin() {
        capturedOrigin = composerFrame
    }

    // MARK: Transitions

    /// Begins a turn. Falls back to an instant pin — no ghost — whenever a
    /// flight would be wrong or impossible.
    func begin(messageID: UUID, text: String, wantsFlight: Bool, reduceMotion: Bool) {
        watchdog?.cancel()
        watchdog = nil

        let canFly = wantsFlight
            && !reduceMotion
            && !UIAccessibility.isVoiceOverRunning
            && capturedOrigin != nil
            && columnFrame != nil

        guard canFly, let origin = capturedOrigin, let column = columnFrame else {
            capturedOrigin = nil
            flight = nil
            phase = .pinned(messageID: messageID)
            return
        }

        phase = .preparing(messageID: messageID)
        flight = Flight(id: messageID, text: text, origin: origin, column: column, pinOffset: nil)
        capturedOrigin = nil

        UIAccessibility.post(notification: .announcement, argument: "Message sent")

        // Hard watchdog. If the ghost is torn down mid-flight — a page swipe to
        // Journal, backgrounding — its completion handler never fires, and
        // without this the real row would stay at opacity 0 permanently.
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: Self.watchdogTimeout)
            guard !Task.isCancelled else { return }
            self?.land(messageID: messageID)
        }
    }

    /// Hands the ghost its destination, which starts beat 1.
    ///
    /// Called once the transcript can say where the new row actually sits, so
    /// the bubble flies to where the message really landed rather than to a
    /// fixed point — which is what makes the motion adapt to how far this
    /// particular send has to travel.
    func launch(messageID: UUID, pinOffset: CGFloat) {
        guard var current = flight, current.id == messageID, current.pinOffset == nil else { return }
        current.pinOffset = pinOffset
        flight = current
    }

    /// The ghost has been laid out at its origin and is now animating.
    func markFlying(messageID: UUID) {
        guard case .preparing(let id) = phase, id == messageID else { return }
        phase = .flying(messageID: messageID)
    }

    /// The ghost has arrived. Drops it and reveals the real row in the *same*
    /// transaction — they are pixel-identical and co-located, so the swap is
    /// invisible; splitting it across two turns flickers.
    func land(messageID: UUID) {
        watchdog?.cancel()
        watchdog = nil
        guard hiddenMessageID == messageID || flight?.id == messageID else { return }
        flight = nil
        phase = .pinned(messageID: messageID)
    }

    /// The user grabbed the scroll view. Stop asserting the pin — do not fight
    /// them, and do not auto-return.
    func release() {
        guard case .pinned = phase else { return }
        phase = .released
    }

    func reset() {
        watchdog?.cancel()
        watchdog = nil
        flight = nil
        capturedOrigin = nil
        phase = .idle
    }

    deinit {
        watchdog?.cancel()
    }
}
