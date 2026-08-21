//
//  SendFlightGhost.swift
//  MeetMemento
//
//  The transient bubble that travels from the chat composer to the transcript
//  pin. Stands in for the real row for the length of the flight, then hands off.
//

import SwiftUI

/// A stand-in for the newly sent user message while it travels.
///
/// Why an overlay rather than `matchedGeometryEffect`: the destination is a
/// lazily-materialised `LazyVStack` row created in the very turn the animation
/// starts, sitting in a scroll view whose offset is changing in that same turn,
/// and the source's content is cleared from the composer before the animation
/// could read it. An overlay sidesteps all three — and its destination is
/// *analytic* (see `ChatTranscriptMetrics.landingRect`), so it is known before
/// the row lays out and does not move while the scroll settles.
///
/// Deliberately not glass. `glassEffectID` morphing needs every participant in
/// one `GlassEffectContainer`, which is impossible across the footer → scroll
/// view boundary — and `ChatInputField` refuses a container by design. Beyond
/// that, animating a glass surface across a scrolling backdrop resamples that
/// backdrop every frame, and the destination is *content*, which is never glass.
/// So this is the bubble from frame one; the composer's capsule stays where it
/// is and collapses on its own curve, and the flight reads as the text lifting
/// off the bar.
struct SendFlightGhost: View {
    let flight: ChatSendChoreographer.Flight
    let pinTopInset: CGFloat
    let animation: Animation
    let onLanded: () -> Void

    @Environment(\.theme) private var theme

    @State private var bubbleSize: CGSize?
    @State private var hasLaunched = false

    /// Shared with `ChatMessageBubble`'s user row so the ghost wraps its text at
    /// exactly the width the row will — see `UserBubbleSurface.maxWidth`.
    private var maxBubbleWidth: CGFloat {
        UserBubbleSurface.maxWidth(inColumnWidth: flight.column.width)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            measuringProbe

            if let bubbleSize {
                flyingBubble(bubbleSize: bubbleSize)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Both mandatory. The transcript carries a whole-list `onTapGesture`
        // that already swallows taps from non-Button descendants; a
        // hit-testable overlay above it would be a fresh instance of that bug.
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Learns the landing size without touching the real row — which may not
    /// have been materialised by the `LazyVStack` yet.
    private var measuringProbe: some View {
        UserBubbleSurface(text: flight.text)
            .frame(maxWidth: maxBubbleWidth, alignment: .trailing)
            .fixedSize(horizontal: false, vertical: true)
            .hidden()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                guard bubbleSize == nil, size.width > 0, size.height > 0 else { return }
                bubbleSize = size
            }
    }

    private func flyingBubble(bubbleSize: CGSize) -> some View {
        // Beat 1's destination: where the row actually landed, which is the pin
        // offset by however far this send still has to scroll. In an empty chat
        // that offset is zero and the ghost flies straight to the pin; in a long
        // thread it lands just above the composer and beat 2 carries it up.
        let pin = ChatTranscriptMetrics.landingRect(
            bubbleSize: bubbleSize,
            column: flight.column,
            pinTopInset: pinTopInset
        )
        let destination = pin.offsetBy(dx: 0, dy: flight.pinOffset ?? 0)

        // Bottom-anchored at the composer, not top-anchored.
        //
        // The capsule is 64pt and a long message is far taller, so aligning tops
        // left the bubble hanging down over the keyboard. Anchoring the bottom
        // edge to the bar's bottom edge makes it grow upward *out* of the bar,
        // and it removes any dependence on the captured origin's height — which
        // is what made a dictated send (a 64pt waveform bar that never laid out
        // with the text) the worst case.
        let start = CGRect(
            x: flight.origin.maxX - bubbleSize.width,
            y: flight.origin.maxY - bubbleSize.height,
            width: flight.origin.width,
            height: bubbleSize.height
        )

        let rect = hasLaunched ? destination : start
        let radius = hasLaunched ? theme.radius.lg : theme.radius.xxl

        // The height is FIXED at the bubble's final height and never animates.
        //
        // It used to animate along with the width, and because this same frame
        // is the clip rect, every bubble taller than the composer was cut off at
        // the bottom for the first part of the flight — 135pt of a ten-line
        // message, the whole third line of a dictated one. Only the width
        // animates now, and it only ever narrows (the composer is wider than the
        // bubble), so the clip can never crop content in either axis.
        return UserBubbleSurface(text: flight.text, cornerRadius: radius)
            .frame(width: bubbleSize.width, height: bubbleSize.height, alignment: .topTrailing)
            .frame(width: rect.width, height: bubbleSize.height, alignment: .topTrailing)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .position(x: rect.midX, y: rect.midY)
            .onAppear { launchIfReady() }
            .onChange(of: flight.pinOffset) { _, _ in launchIfReady() }
    }

    /// Starts beat 1, but only once the transcript has said where the row landed.
    ///
    /// Until then the ghost simply sits on the composer showing the message,
    /// which is what the user expects to see anyway — the text has not left the
    /// bar yet.
    private func launchIfReady() {
        guard !hasLaunched, flight.pinOffset != nil else { return }
        withAnimation(animation) {
            hasLaunched = true
        } completion: {
            onLanded()
        }
    }
}
