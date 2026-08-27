//
//  Spacing.swift
//  MeetMemento
//
//  Created by Claude Code
//  Semantic spacing scale and constants for consistent UI spacing
//

import Foundation
import SwiftUI

/// Semantic spacing scale for consistent padding, margins, and gaps throughout the app
struct Spacing {
    // MARK: - Spacing Scale

    /// Minimal gaps (4pt)
    static let xxs: CGFloat = 4

    /// Tight spacing (8pt)
    static let xs: CGFloat = 8

    /// Compact spacing (12pt)
    static let sm: CGFloat = 12

    /// Standard spacing (16pt) - default for most UI elements
    static let md: CGFloat = 16

    /// Comfortable spacing (20pt)
    static let lg: CGFloat = 20

    /// Spacious (24pt)
    static let xl: CGFloat = 24

    /// Section breaks (32pt)
    static let xxl: CGFloat = 32

    /// Major sections (40pt)
    static let xxxl: CGFloat = 40

    // MARK: - Opacity Constants

    /// Standard opacity values for consistent visual hierarchy
    struct Opacity {
        // MARK: - Minimal Opacity (0.01-0.08)

        /// Nearly invisible, for hit testing areas (0.01)
        static let invisible: Double = 0.01

        /// Very faint background tints (0.04)
        static let faint: Double = 0.04

        /// Very subtle shadows (0.06)
        static let shadow: Double = 0.06

        /// Subtle skeleton loading backgrounds (0.08)
        static let skeleton: Double = 0.08

        // MARK: - Low Opacity (0.1-0.2)

        /// Light background tints (0.1)
        static let tint: Double = 0.1

        /// Light fill backgrounds (0.12)
        static let fill: Double = 0.12

        /// Border opacity (0.15)
        static let border: Double = 0.15

        /// Overlay backgrounds (0.2)
        static let overlay: Double = 0.2

        // MARK: - Medium Opacity (0.3-0.5)

        /// Subtle overlays and backgrounds (0.3)
        static let subtle: Double = 0.3

        /// Medium prominence (0.4)
        static let medium: Double = 0.4

        /// Half opacity (0.5)
        static let half: Double = 0.5

        // MARK: - High Opacity (0.6-0.9)

        /// Disabled state (0.6)
        static let disabled: Double = 0.6

        /// Prominent but not full (0.8)
        static let strong: Double = 0.8

        /// Nearly opaque (0.9)
        static let prominent: Double = 0.9

        /// Muted text or UI elements (0.95)
        static let muted: Double = 0.95
    }

    // MARK: - Animation Durations

    /// Standard animation duration constants
    struct Duration {
        /// Fast animations (0.1s) - quick transitions
        static let fast: CGFloat = 0.1

        /// Standard animations (0.15s) - default duration
        static let standard: CGFloat = 0.15

        /// Slow animations (0.3s) - deliberate transitions
        static let slow: CGFloat = 0.3
    }
}

// MARK: - Motion

/// Named animation curves. Previously every call site inlined its own spring
/// literal; anything shared across files belongs here instead.
enum Motion {
    /// Chat send choreography: the user's bubble travelling from the composer
    /// to its pinned rest position.
    ///
    /// A spring is correct here only because the composer no longer drops
    /// focus on send — see the note in `ChatInputField.sendMessage()`. If the
    /// keyboard is ever dismissed on send again, this has to go back to an
    /// ease curve so it does not fight the system keyboard's own timing.
    static let sendFlight: Animation = .spring(duration: 0.42, bounce: 0.10)

    /// Empty state ↔ transcript cross-fade.
    static let transcriptCrossFade: Animation = .easeOut(duration: 0.2)

    static let narrationDissolveOutDuration: TimeInterval = 0.42
    static let narrationDissolveInDuration: TimeInterval = 0.55
    static let narrationDissolveInDelay: TimeInterval = 0.08
    static let narrationDissolveReducedDuration: TimeInterval = 0.18

    /// Composer ↔ narration: outgoing plate. Ease-in so copy is gone
    /// before the incoming plate is readable — a symmetric easeInOut
    /// double-exposes the two h2 headlines at different positions.
    static let narrationDissolveOut: Animation = .easeIn(duration: narrationDissolveOutDuration)

    /// Composer ↔ narration: incoming plate. Delayed ease-out so it
    /// resolves into a mostly clear field.
    static let narrationDissolveIn: Animation = .easeOut(duration: narrationDissolveInDuration)
        .delay(narrationDissolveInDelay)

    /// Reduce Motion: opacity-only cut, no delay, no blur (PRES-094).
    static let narrationDissolveReduced: Animation = .easeOut(duration: narrationDissolveReducedDuration)

    /// Peak blur (pt) at the mix of the two plates. Envelope is
    /// `4 * p * (1 - p) * narrationDissolveBlur`, so 0 at both rest states.
    static let narrationDissolveBlur: CGFloat = 12

    /// Beat 2 of the send choreography: the transcript easing the just-landed
    /// message up to the pin.
    ///
    /// Scaled by distance, because the send that scrolls 40pt and the send that
    /// scrolls 900pt are the same gesture and should not take the same time —
    /// a fixed curve makes the short one feel sluggish and the long one feel
    /// like a jump. Clamped at both ends so a very long thread never drags.
    ///
    /// `bounce: 0` is deliberate and is NOT a "spring settle": a zero-bounce
    /// spring is critically damped, so it never overshoots. It is the same
    /// curve `Animation.smooth(duration:)` produces, and its decelerating shape
    /// is what lets beat 2 pick up the momentum beat 1's ghost put down instead
    /// of reading as a second, separate launch. An ease-in-out would be worse,
    /// not better — ease-in starts at zero velocity, which contradicts that
    /// hand-off. If this ever reads as a jump again the cause is upstream of
    /// the curve: see `PinIntent.settling` in `ChatMessagesView`.
    static func sendScroll(distance: CGFloat) -> Animation {
        .spring(duration: sendScrollDuration(distance: distance), bounce: 0)
    }

    /// How long `sendScroll` runs, in seconds.
    ///
    /// Extracted so the view can *time* the settle rather than ask SwiftUI when
    /// the scroll finished: a `ScrollViewProxy` scroll is not a view-tree
    /// animation, so there is no contract that it reports through
    /// `withAnimation`'s completion handler. The duration is analytic, so
    /// timing it needs no such contract.
    static func sendScrollDuration(distance: CGFloat) -> Double {
        let span = min(max(abs(distance), 0), sendScrollFullTravel)
        let progress = sendScrollFullTravel > 0 ? span / sendScrollFullTravel : 0
        return sendScrollMinDuration
            + (sendScrollMaxDuration - sendScrollMinDuration) * Double(progress)
    }

    /// How long the transcript must be left entirely alone once beat 2 starts:
    /// the animation's own duration plus a couple of frames, so the pin is
    /// handed back to the corrective pass *after* the last animated frame
    /// rather than on it.
    static func sendScrollSettleWindow(distance: CGFloat) -> Double {
        sendScrollDuration(distance: distance) + sendScrollSettleSlack
    }

    /// Distance at which `sendScroll` reaches its longest duration. Roughly one
    /// viewport — beyond that the motion is already reading as "a long way".
    private static let sendScrollFullTravel: CGFloat = 700
    private static let sendScrollMinDuration: Double = 0.25
    private static let sendScrollMaxDuration: Double = 0.50
    /// ~3 frames at 60Hz. Long enough to absorb a dropped frame, short enough
    /// that the pin is unguarded for no meaningful window.
    private static let sendScrollSettleSlack: Double = 0.05
}
