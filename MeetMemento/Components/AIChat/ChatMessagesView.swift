//
//  ChatMessagesView.swift
//  MeetMemento
//
//  Shared thread for Chat's typing and narration modes: empty state, bubbles,
//  loading row, header clearance, and footer reserve.
//

import Combine
import SwiftUI

struct ChatMessagesView: View {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject var voiceService: VoicePlaybackService
    @ObservedObject var choreographer: ChatSendChoreographer
    var hasEntries: Bool
    var bottomReserve: CGFloat
    var followTail: Bool
    /// Starter prompts for the empty state. Empty hides the chips entirely —
    /// which is what an archive with nothing in it should show.
    var suggestions: [String] = []
    var onCitations: ([JournalCitation]) -> Void
    var onDismissKeyboard: () -> Void
    var onSuggestionTap: (String) -> Void = { _ in }

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Visible content height — container minus both safe-area insets. Read
    /// from `ScrollGeometry` rather than derived by hand.
    @State private var viewportHeight: CGFloat = 0
    /// Top of the pinned user message, tagged with the row it came from so a
    /// measurement of the *previous* turn can be rejected rather than silently
    /// mixed into `activeTurnHeight`.
    @State private var lastUserTop: PinnedRowTop?
    /// End of the real transcript (before the reserve), in `ChatSpace.content`.
    @State private var transcriptEndY: CGFloat = 0
    @State private var pin: PinIntent = .none
    @State private var pinCorrectionsLeft = 0
    /// The content height the remaining corrections are budgeted against.
    @State private var pinCorrectionHeight: CGFloat = -1
    /// Hard ceiling on corrections for one send, independent of the per-layout
    /// allowance.
    ///
    /// The per-layout refill exists so a transcript that is still growing always
    /// has corrections available — but a correction can itself change the
    /// content height (it moves the offset, which moves the reserve), which
    /// refills the allowance, which permits another correction. That is a loop
    /// with no fixed point, and it spins the run loop hard enough that the app
    /// never goes idle. This bounds it.
    @State private var pinCorrectionsTotal = 0
    /// How far beat 2 has to travel, captured when beat 1 launches. Drives the
    /// scroll's duration so a short send and a long one do not take equally long.
    @State private var beatTwoDistance: CGFloat = 0
    /// One timer, two disjoint jobs — the `.pending` watchdog, then the
    /// `.settling` hand-back. A send is never in both states at once, and both
    /// must die together on release, transcript replacement, and disappear.
    @State private var pinTimer: Task<Void, Never>?
    @State private var sessionSettleTask: Task<Void, Never>?

    private let followClock = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    private static let bottomAnchorID = "chat-transcript-end"
    /// Sub-point drift is invisible and not worth a scroll.
    private static let pinTolerance: CGFloat = 0.5
    /// Corrections allowed against any one content height. Deliberately per
    /// *layout*, not per send: a send is followed by a burst of layouts as the
    /// placeholder, the loading row and the composer all settle, and a per-send
    /// budget is spent on those transient frames long before the transcript
    /// reaches its final height — which strands the pin short with no
    /// allowance left to fix it.
    private static let pinCorrectionBudget = 4
    /// Generous, because exceeding it means giving up on the pin for this turn —
    /// but finite, because the alternative is an unbounded feedback loop.
    private static let pinCorrectionTotalBudget = 12

    /// Set by `ChatSendPinUITests`. Compiled out of release builds entirely.
    private static var usesInstantSendScroll: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-InstantSendScroll")
        #else
        false
        #endif
    }
    /// Insurance only. The gate in `updatePin` is measurement-driven and
    /// normally opens on the very next layout.
    ///
    /// 400ms, not 200. The send turn is the busiest one in the app — two
    /// appends, a LazyVStack diff, the composer collapsing, the ghost's
    /// measuring probe — and when this timeout wins the race it does not merely
    /// land short: it lands the ghost too, so beat 1 AND beat 2 are skipped and
    /// the whole send reads as a jump. Being late costs one invisible frame
    /// before a fallback nobody should ever see; being early costs the
    /// choreography.
    private static let pinDeferralTimeout: Duration = .milliseconds(400)

    private var showsEmptyState: Bool {
        viewModel.messages.isEmpty && !viewModel.isLoading
    }

    private var lastUserMessageID: UUID? {
        viewModel.messages.last(where: { $0.isFromUser })?.id
    }

    /// The reply Regenerate applies to — the last one, and only when it is the
    /// final row in the transcript.
    private var lastAssistantMessageID: UUID? {
        guard let last = viewModel.messages.last, !last.isFromUser else { return nil }
        return last.id
    }

    /// Slack below the transcript that makes the pin reachable.
    /// See `ChatTranscriptMetrics.reserve` for the invariant this maintains.
    private var reserve: CGFloat {
        ChatTranscriptMetrics.reserve(
            viewportHeight: viewportHeight,
            pinnedRowID: lastUserMessageID,
            measurement: lastUserTop,
            transcriptEndY: transcriptEndY
        )
    }

    var body: some View {
        ScrollViewReader { proxy in
            ZStack {
                transcript(proxy: proxy)
                emptyStateLayer
            }
            .accessibleAnimation(Motion.transcriptCrossFade, value: showsEmptyState)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear
                    .frame(height: bottomReserve)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .onChange(of: viewModel.lastSend) { _, ticket in
                handleSend(ticket, proxy: proxy)
            }
            .onChange(of: viewModel.transcriptGeneration) { _, _ in
                handleTranscriptReplaced(proxy: proxy)
            }
            // Beat 2 starts on the ghost's landing, never on a timer, so the
            // handoff to the real row and the scroll that moves it cannot race.
            .onChange(of: choreographer.phase) { _, newPhase in
                guard case .pinned(let landedID) = newPhase,
                      case .flying(let id, let seq) = pin,
                      landedID == id
                else { return }
                runBeatTwo(proxy: proxy, id: id, seq: seq)
            }
            .onReceive(followClock) { _ in
                guard followTail else { return }
                withAccessibleAnimation(.easeOut(duration: 0.4), reduceMotion: reduceMotion) {
                    proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                }
            }
            .onDisappear {
                sessionSettleTask?.cancel()
                sessionSettleTask = nil
                pinTimer?.cancel()
                pinTimer = nil
                pin = .none
                choreographer.reset()
            }
        }
    }

    // MARK: - Transcript

    private func transcript(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                // 16pt is the gap *within* a turn — between a question and its
                // answer. `turnTrailingGap` adds the other 16 after a completed
                // reply, so consecutive turns still read as separate blocks.
                LazyVStack(alignment: .leading, spacing: Spacing.md) {
                    ForEach(viewModel.messages) { message in
                        bubble(for: message)
                            .id(message.id)
                            // The flying ghost is standing in for this row.
                            .opacity(choreographer.hiddenMessageID == message.id ? 0 : 1)
                            .modifier(TurnTopReporter(
                                messageID: message.id,
                                isTarget: message.id == lastUserMessageID,
                                report: { lastUserTop = $0 }
                            ))
                            // Applied AFTER the reporter so it can never shift
                            // the measured top of a pinned row.
                            .padding(.bottom, turnTrailingGap(for: message))
                    }

                    if viewModel.isLoading {
                        AILoadingState(phrase: viewModel.loadingPhrase)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .id("loading-state")
                    }
                }

                // The tail lives OUTSIDE the LazyVStack deliberately. As
                // siblings inside it, the end marker and the reserve would each
                // inherit the row spacing — phantom slack that would let the
                // user drag the pinned bubble up above the pin.
                Color.clear
                    .frame(height: 1)
                    .id(Self.bottomAnchorID)
                    .onGeometryChange(for: CGFloat.self) {
                        $0.frame(in: .named(ChatSpace.content)).maxY
                    } action: { transcriptEndY = $0 }

                Color.clear
                    .frame(height: reserve)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    // Never animate. The reserve exists to cancel content
                    // growth frame-for-frame; animating it would make it lag
                    // the growth it is cancelling, and the pin would drift.
                    .animation(nil, value: reserve)
            }
            .coordinateSpace(.named(ChatSpace.content))
        }
        // A safe-area inset, not padding: it shrinks the scroll view's visible
        // rect, which is the rect `scrollTo(_:anchor:)` resolves against. That
        // is what makes `anchor: .top` land on the pin for every message rather
        // than only the first.
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear
                .frame(height: AppHeaderMetrics.chatPinTopInset)
                // `Color` is hit-testable. Without this, a drag started
                // anywhere in the top band would never reach the scroll view.
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .scrollIndicators(.hidden)
        // Same 16pt gutter as header/footer. Padding is ignored
        // under RootPageScaffold's `.ignoresSafeArea()`.
        .rootEdgeInset()
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(ChatSpace.page)) }
            action: { choreographer.columnFrame = $0 }
        .onScrollGeometryChange(for: ScrollSnapshot.self) { geometry in
            ScrollSnapshot(
                // `bounds.height`, NOT `containerSize - contentInsets`.
                //
                // The scroll range is `contentSize.height - bounds.height`, and
                // the safe-area inset regions that buy the header clearance and
                // the footer reserve are already laid out as part of the scroll
                // *content*. Subtracting the insets as well double-counts them —
                // it under-reported the viewport by the keyboard's height here,
                // which under-sized the reserve by the same amount and left the
                // pin permanently out of reach with the keyboard up.
                viewport: geometry.bounds.height,
                contentHeight: geometry.contentSize.height,
                insetTop: geometry.contentInsets.top,
                offsetY: geometry.contentOffset.y
            )
        } action: { _, snapshot in
            // `offsetY` is in the observed key deliberately: a clamp IS a change
            // in the offset, and the corrective pass has to see the frame it
            // lands on. The action is O(1) and returns immediately unless a pin
            // is live, and the transform already ran every frame before this.
            if snapshot.viewport != viewportHeight { viewportHeight = snapshot.viewport }
            updatePin(proxy: proxy, snapshot: snapshot)
        }
        .onScrollPhaseChange { _, newPhase in
            // Two different releases, deliberately. `.tracking` is
            // finger-down-but-not-yet-moved — i.e. a tap to dismiss the
            // keyboard — and that must not hand the scroll offset back, or the
            // pin sags the moment the keyboard falls. Only a real drag does.
            // `.interacting` only. A user drag always passes through it
            // (tracking -> interacting -> decelerating), so it is sufficient on
            // its own — and excluding `.decelerating` means beat 2's own
            // animated scroll can never be mistaken for the user taking over
            // and drop the pin it just established.
            if newPhase == .interacting {
                pin = .none
                // A settle timer from this turn must not drag the pin back into
                // `.holding` behind the user's finger. Its identity guard
                // already refuses, but there is no reason to keep it alive.
                pinTimer?.cancel()
                pinTimer = nil
            }
            if newPhase == .interacting || newPhase == .tracking {
                choreographer.release()
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollContentBackground(.hidden)
        .background(.clear)
        // `.soft`, not hidden. Hidden left the transcript fully crisp behind the
        // header: `AppHeader` puts blur only in the Dynamic Island strip so its
        // glass can sample content, which meant the previous turn scrolled up
        // *behind* the header buttons at full contrast. Measured at the resting
        // pin, the previous reply's action bar sits at y=105–125 while the
        // header buttons occupy y=62–110 — the Journal button lands on top of
        // "Read aloud", so tapping the visible control navigated away instead.
        // The soft edge is the system treatment for text content: it fades the
        // band under the bar so nothing there reads as tappable.
        .scrollEdgeEffectStyle(.soft, for: .top)
        // ⚠️ This gesture spans the whole message list, and it will SWALLOW
        // taps from any descendant that is not a `Button`. A plain
        // `.onTapGesture` on a child loses to it across the ScrollView
        // boundary, and the child silently stops responding — that is
        // exactly how the citations modal broke once (CitationLink was
        // briefly reimplemented with `.onTapGesture` instead of `Button`).
        .onTapGesture {
            onDismissKeyboard()
        }
    }

    /// Extra gap after a completed assistant reply, so the 16pt that separates
    /// a question from its answer grows back to 32pt between turns.
    ///
    /// Deliberately nothing for the empty placeholder appended at send: it
    /// draws no content, and padding it would open a visible gap above the
    /// "thinking" indicator. Mirrors `ChatMessageBubble`'s own emptiness rule.
    private func turnTrailingGap(for message: ChatMessage) -> CGFloat {
        guard !message.isFromUser else { return 0 }

        if let ai = message.aiOutputContent {
            let isEmpty = ai.body.isEmpty
                && (ai.heading1 ?? "").isEmpty
                && (ai.heading2 ?? "").isEmpty
                && (ai.citations?.isEmpty ?? true)
            if isEmpty { return 0 }
        } else if message.content.isEmpty {
            return 0
        }

        return Spacing.md
    }

    /// Kept mounted alongside the transcript rather than swapped with it.
    ///
    /// As an `if/else` the scroll view did not exist until the send turn, so
    /// its geometry could not be trusted for the very first message — and the
    /// first message is exactly the case the reserve exists to serve.
    private var emptyStateLayer: some View {
        emptyState
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Same 16pt column as the transcript. Padding is ignored under
            // RootPageScaffold's `.ignoresSafeArea()`; this is not.
            .rootEdgeInset()
            .opacity(showsEmptyState ? 1 : 0)
            .allowsHitTesting(showsEmptyState)
            .accessibilityHidden(!showsEmptyState)
    }

    // MARK: - Send choreography

    private func handleSend(_ ticket: ChatViewModel.SendTicket?, proxy: ScrollViewProxy) {
        guard let ticket,
              let message = viewModel.messages.first(where: { $0.id == ticket.userMessageID })
        else { return }

        // Deliberately NO scroll here.
        //
        // The row was appended in this very update, so the layout a `scrollTo`
        // would resolve against is the one still on screen — the previous
        // turn's, whose reserve is sized for the previous turn. Against that
        // layout the pin is `viewport - newTurnHeight` outside the scroll
        // range, and a scroll past the range does not fail, it CLAMPS: the
        // transcript lands ~450pt short while the ghost, whose destination is
        // analytic, flies to the real pin regardless. That mismatch is exactly
        // what read as the bubble snapping back down after the animation.
        //
        // Record the intent instead. `updatePin` performs it from the first
        // layout that can actually reach the pin, which is the very next one:
        // `reserve` returns the full viewport for as long as no measurement
        // tagged with THIS row exists.
        pin = .pending(id: ticket.userMessageID, seq: ticket.seq)
        pinCorrectionsLeft = Self.pinCorrectionBudget
        pinCorrectionsTotal = Self.pinCorrectionTotalBudget
        pinCorrectionHeight = -1
        beatTwoDistance = 0
        armPinWatchdog(proxy: proxy)

        // A ghost only for composer sends. Narration has no composer on screen,
        // and regenerate/retry re-use a bubble the user has already seen —
        // flying either would be a lie about where it came from.
        choreographer.begin(
            messageID: ticket.userMessageID,
            text: message.content,
            imageJPEGs: message.imageJPEGs,
            wantsFlight: ticket.origin == .composer && !followTail,
            reduceMotion: reduceMotion
        )
    }

    /// The single authority over the transcript's resting offset.
    ///
    /// Driven by the scroll-geometry observer, which fires on every layout that
    /// changes the content, the viewport, the insets or the offset — including
    /// the first layout containing the row being pinned, and every frame on
    /// which something clamps.
    private func updatePin(proxy: ScrollViewProxy, snapshot: ScrollSnapshot) {
        switch pin {
        case .none:
            return

        case .pending(let id, let seq):
            // Two conditions, both measured, neither a delay: the row being
            // pinned has reported its own top, and the transcript as laid out is
            // tall enough for that top to be reachable.
            //
            // This cannot deadlock. If the tagged measurement arrives after this
            // callback, it changes `reserve`, which changes `contentSize`, which
            // re-fires the observer — and the new turn always has height, so the
            // re-fire is guaranteed.
            guard let top = lastUserTop, top.id == id,
                  ChatTranscriptMetrics.pinIsReachable(
                      pinOffset: top.y,
                      contentHeight: snapshot.contentHeight,
                      viewportHeight: snapshot.viewport
                  )
            else { return }

            pinTimer?.cancel()
            pinTimer = nil

            // How far below the pin the row currently sits — beat 2's travel,
            // and beat 1's destination expressed as an offset from the pin.
            let offset = ChatTranscriptMetrics.pinDelta(
                rowTopInContent: top.y,
                contentOffsetY: snapshot.offsetY,
                contentInsetTop: snapshot.insetTop
            )
            beatTwoDistance = offset

            if choreographer.flight?.id == id {
                // Beat 1: hand the ghost its destination and let it fly. The
                // transcript deliberately does NOT move yet — it used to jump
                // here, instantly and by up to a full viewport, while every
                // other row translated under an unrelated bubble animation.
                choreographer.launch(messageID: id, pinOffset: offset)
                pin = .flying(id: id, seq: seq)
            } else {
                // No ghost (Reduce Motion, VoiceOver, narration, retry,
                // regenerate): there is no beat 1 to wait for.
                runBeatTwo(proxy: proxy, id: id, seq: seq)
            }

        case .flying, .settling:
            // Beat 1 owns the screen, then beat 2 does. Neither may be
            // corrected mid-motion; the `.holding` pass repairs whatever they
            // leave behind, on the first layout after the settle.
            return

        case .holding(let id, _):
            // Corrective re-assert. Every clamp this feature can suffer shows up
            // here as a non-zero delta: the loading row leaving the stack at
            // stream end, the keyboard falling (the visible rect grows a frame
            // before the reserve compensates), a measurement landing late.
            //
            // Excluded during narration: `followClock` deliberately pulls to the
            // transcript tail, which is BELOW the pin while the turn is shorter
            // than the viewport. Two authorities over one offset would fight.
            guard !followTail, let top = lastUserTop, top.id == id else { return }

            let delta = ChatTranscriptMetrics.pinDelta(
                rowTopInContent: top.y,
                contentOffsetY: snapshot.offsetY,
                contentInsetTop: snapshot.insetTop
            )
            guard abs(delta) > Self.pinTolerance,
                  ChatTranscriptMetrics.pinIsReachable(
                      pinOffset: top.y,
                      contentHeight: snapshot.contentHeight,
                      viewportHeight: snapshot.viewport
                  )
            else { return }

            // A layout this pass has not seen before is a fresh opportunity, so
            // it refills the allowance. The budget therefore bounds only
            // *repeated* attempts against one unchanging content height — the
            // single shape in which this could spin — while a transcript that is
            // still growing always has corrections available.
            if snapshot.contentHeight != pinCorrectionHeight {
                pinCorrectionHeight = snapshot.contentHeight
                pinCorrectionsLeft = Self.pinCorrectionBudget
            }
            guard pinCorrectionsLeft > 0, pinCorrectionsTotal > 0 else { return }

            // Cannot oscillate: `anchor: .top` never overshoots, so this either
            // reaches the pin (delta -> 0, no further correction) or clamps to a
            // stable offset (no further geometry change, no further callback).
            pinCorrectionsLeft -= 1
            pinCorrectionsTotal -= 1
            snap(proxy: proxy) { $0.scrollTo(id, anchor: .top) }
        }
    }

    /// Beat 2: ease the just-landed message up to the pin.
    ///
    /// Animated, unlike every other scroll in this file. The corrective
    /// re-asserts in `.holding` stay instant on purpose — those are clamp
    /// repairs, and animating a one-frame correction would make it visible.
    ///
    /// The state written below is the whole of the "there is no scroll, it just
    /// jumps" bug. This used to enter `.holding` *before* starting the
    /// animation, so the very first animated frame reached
    /// `onScrollGeometryChange` with the pin already correctable: `updatePin`
    /// saw a delta of nearly the full travel, read it as a clamp, and re-issued
    /// `scrollTo` inside `disablesAnimations` — overriding an animation that was
    /// one frame old. `.settling` is the state in which the transcript is moving
    /// deliberately and nothing may touch it.
    private func runBeatTwo(proxy: ScrollViewProxy, id: UUID, seq: Int) {
        pinTimer?.cancel()
        pinTimer = nil

        let distance = beatTwoDistance

        // Already on the pin: nothing to animate, nothing to protect.
        guard abs(distance) > Self.pinTolerance else {
            beginHolding(id: id, seq: seq)
            return
        }

        // Reduce Motion: one instant step, and again nothing to protect. This
        // deliberately does not route through `withAccessibleAnimation` — the
        // settle has to be timed, and there is no window to time when the
        // scroll takes zero seconds.
        guard !reduceMotion else {
            snap(proxy: proxy) { $0.scrollTo(id, anchor: .top) }
            beginHolding(id: id, seq: seq)
            return
        }

        // UI tests take the instant path. XCUITest synchronises by waiting for
        // the app to go idle, and it cannot resolve an animated
        // `ScrollViewProxy` scroll — every query after one issues blocks until
        // it times out. The animation is the product behaviour and stays on for
        // real users; what the UI test actually asserts is the resting
        // position, which is identical either way.
        guard !Self.usesInstantSendScroll else {
            snap(proxy: proxy) { $0.scrollTo(id, anchor: .top) }
            beginHolding(id: id, seq: seq)
            return
        }

        pin = .settling(id: id, seq: seq)
        withAnimation(Motion.sendScroll(distance: distance)) {
            proxy.scrollTo(id, anchor: .top)
        }

        // Timed, not observed.
        //
        // `withAnimation(_:completionCriteria:_:completion:)` exists, but a
        // `ScrollViewProxy` scroll is not a view-tree animation and there is no
        // contract that it reports back through that channel. A completion that
        // never fired would strand the pin in `.settling` for the rest of the
        // reply, with no corrective pass left to repair the loading row leaving
        // at stream end — the one clamp that always happens. The duration is
        // analytic, so timing it needs no such contract.
        pinTimer = Task { @MainActor in
            try? await Task.sleep(
                for: .seconds(Motion.sendScrollSettleWindow(distance: distance))
            )
            // Identity-checked, not merely cancellation-checked. A drag
            // mid-settle already moved `pin` to `.none` via
            // `onScrollPhaseChange`, and a newer send would have moved it to a
            // higher `seq`. Neither may be dragged back into `.holding` by this
            // turn's timer.
            guard !Task.isCancelled, pin == .settling(id: id, seq: seq) else { return }
            beginHolding(id: id, seq: seq)
        }
    }

    /// Hands the offset back to the corrective pass with a fresh allowance —
    /// the first layout after a settle is one that pass has never seen.
    private func beginHolding(id: UUID, seq: Int) {
        pinCorrectionHeight = -1
        pinCorrectionsLeft = Self.pinCorrectionBudget
        pin = .holding(id: id, seq: seq)
    }

    /// Insurance only: if the measured gate somehow never opens, assert anyway.
    /// A short landing the corrective pass can repair beats a transcript that
    /// never moved at all.
    private func armPinWatchdog(proxy: ScrollViewProxy) {
        pinTimer?.cancel()
        pinTimer = Task { @MainActor in
            try? await Task.sleep(for: Self.pinDeferralTimeout)
            guard !Task.isCancelled, case .pending(let id, let seq) = pin else { return }
            pinTimer = nil   // this job is done; runBeatTwo re-arms it for the settle

            // Nothing was ever measured, so there is no travel to scale the
            // curve by — take the viewport as the upper bound. `anchor: .top`
            // clamps at the pin either way, and a scroll the user can see beats
            // a teleport. Land the ghost first so the scroll carries the real
            // row rather than a stalled stand-in.
            beatTwoDistance = max(viewportHeight, 1)
            choreographer.land(messageID: id)
            runBeatTwo(proxy: proxy, id: id, seq: seq)
        }
    }

    /// A different conversation is now on screen — not merely a new id for the
    /// one that already was.
    ///
    /// Driven by `ChatViewModel.transcriptGeneration`, never by
    /// `currentSessionId`: the id is minted mid-conversation on a new chat's
    /// first reply, and reacting to that scrolled the reader away from the
    /// answer they were watching arrive and killed the pin for the rest of the
    /// turn.
    private func handleTranscriptReplaced(proxy: ScrollViewProxy) {
        choreographer.reset()
        pin = .none
        lastUserTop = nil
        pinTimer?.cancel()
        pinTimer = nil
        sessionSettleTask?.cancel()
        sessionSettleTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            // Land on the most recent exchange, the way every messaging app
            // opens a thread.
            snap(proxy: proxy) { $0.scrollTo(Self.bottomAnchorID, anchor: .bottom) }
        }
    }

    private func snap(proxy: ScrollViewProxy, _ body: (ScrollViewProxy) -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { body(proxy) }
    }

    private func bubble(for message: ChatMessage) -> some View {
        ChatMessageBubble(
            message: message,
            animate: message.isNew,
            isStreaming: message.isStreaming,
            feedbackType: viewModel.feedbackType(for: message.id),
            isSpeaking: voiceService.speakingMessageID == message.id,
            isPaused: voiceService.speakingMessageID == message.id && voiceService.isPaused,
            onCitationsTapped: {
                if let citations = message.citations, !citations.isEmpty {
                    onCitations(citations)
                }
            },
            onSpeak: message.isFromUser ? nil : {
                if let ai = message.aiOutputContent {
                    voiceService.toggleSpeech(
                        messageID: message.id,
                        heading1: ai.heading1,
                        heading2: ai.heading2,
                        body: ai.body
                    )
                }
            },
            // Last reply only. Regenerating an older one re-sends it, which
            // appends at the end — so offering it mid-transcript promised a
            // reordering nobody wants (and `regenerateResponse` now refuses it,
            // which would leave a dead button here).
            onRedo: message.id == lastAssistantMessageID ? {
                voiceService.stopIfSpeaking(messageID: message.id)
                viewModel.regenerateResponse(for: message.id)
            } : nil,
            onThumbsUp: message.isFromUser ? nil : {
                viewModel.toggleThumbsUp(for: message.id)
            },
            onThumbsDown: message.isFromUser ? nil : {
                viewModel.toggleThumbsDown(for: message.id)
            },
            isReported: viewModel.isReported(message.id),
            onReportAnswer: message.isFromUser ? nil : {
                viewModel.beginFeedback(messageID: message.id, source: .report)
            },
            onRetry: message.isFromUser ? { viewModel.retryMessage(message) } : nil,
            onAnimationComplete: { viewModel.markMessageSeen(message.id) }
        )
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Spacer(minLength: 0)

            VStack(spacing: Spacing.md) {
                VStack(spacing: Spacing.xs) {
                    Image("LaunchLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)

                    Text("Let\u{2019}s dive deeper\ninto your journal")
                        .font(type.h2)
                        .foregroundStyle(PrimaryScale.primary600)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, AppHeaderMetrics.edgeInset)
                }

                if !hasEntries {
                    Text("Write a journal entry first — then I can reflect it back to you, and show you which entries I drew from.")
                        .font(type.body1)
                        .foregroundStyle(theme.mutedForeground)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, AppHeaderMetrics.edgeInset)
                } else if !suggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: Spacing.md) {
                            ForEach(suggestions, id: \.self) { suggestion in
                                AISuggestionCard(suggestion: suggestion) {
                                    onSuggestionTap(suggestion)
                                }
                            }
                        }
                    }
                    .scrollClipDisabled()
                    .isolateFromPagingScroll()
                }
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)
        }
        .padding(.top, AppHeaderMetrics.contentTopPadding)
    }
}

// MARK: - Geometry reporting

/// Reports the top of the pinned row in `ChatSpace.content`.
///
/// Content space, not `.global`: it is scroll-invariant, so this fires on real
/// layout changes only. In global space it would fire every scroll frame and
/// churn `@State` for the whole length of a reply.
private struct TurnTopReporter: ViewModifier {
    let messageID: UUID
    let isTarget: Bool
    let report: (PinnedRowTop) -> Void

    func body(content: Content) -> some View {
        // Applied unconditionally and gated inside the action, not by an `if`.
        // As a branch this was `_ConditionalContent`: the row that stopped being
        // the target — and the one that became it — changed structural identity
        // on every send, tearing down their `@State` with it.
        content.onGeometryChange(for: CGFloat.self) {
            $0.frame(in: .named(ChatSpace.content)).minY
        } action: { y in
            guard isTarget else { return }
            report(PinnedRowTop(id: messageID, y: y))
        }
    }
}

/// What the send choreography is currently trying to hold on screen.
///
/// Separate from `ChatSendChoreographer.Phase` on purpose: that phase is about
/// the ghost, this is about the scroll view. A tap that dismisses the keyboard
/// releases the former; only a real drag should release the latter.
private enum PinIntent: Equatable {
    case none
    /// A send was observed. Waiting for a layout that can actually reach the pin.
    case pending(id: UUID, seq: Int)
    /// Beat 1: the ghost is flying to where the row landed. The transcript must
    /// stay exactly where it is — beat 2 is what moves it.
    case flying(id: UUID, seq: Int)
    /// Beat 2: the transcript is animating up to the pin, on purpose. Nothing
    /// may correct the offset here — the corrective pass runs inside a
    /// `disablesAnimations` transaction, so a single frame of it overrides the
    /// animation and turns beat 2 into a teleport.
    case settling(id: UUID, seq: Int)
    /// Landed on the pin. Hold it against clamps until the user takes over.
    case holding(id: UUID, seq: Int)
}

/// The scroll-view facts the pin logic needs, in one equatable value so a single
/// observer replaces one per quantity.
private struct ScrollSnapshot: Equatable {
    var viewport: CGFloat = 0
    var contentHeight: CGFloat = 0
    var insetTop: CGFloat = 0
    var offsetY: CGFloat = 0
}
