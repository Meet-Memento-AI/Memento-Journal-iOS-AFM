//
//  NarrationContentDissolve.swift
//  MeetMemento
//
//  Photographic dissolve between Chat's typing plate and narration plate.
//  Progress is animatable so blur peaks at the mix and is exactly 0 at rest.
//

import SwiftUI

extension View {
    /// Cross-dissolve this plate in or out as `isVisible` changes.
    ///
    /// Outgoing uses `Motion.narrationDissolveOut` (ease-in); incoming uses
    /// `Motion.narrationDissolveIn` (delayed ease-out). Layout of the wrapped
    /// content is not interpolated — only opacity, and blur when `blurs` is
    /// true. Glass chrome should pass `blurs: false`.
    func narrationDissolve(isVisible: Bool, blurs: Bool = true) -> some View {
        modifier(NarrationContentDissolve(isVisible: isVisible, blurs: blurs))
    }
}

private struct NarrationContentDissolve: ViewModifier {
    var isVisible: Bool
    var blurs: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            // When `isVisible` flips, do not interpolate the plate's own
            // layout (`bottomReserve`, padding). Only DissolvePlate's
            // progress should ride the curve.
            .animation(nil, value: isVisible)
            .modifier(DissolvePlate(
                progress: isVisible ? 1 : 0,
                blurs: blurs && !reduceMotion
            ))
            .animation(curve, value: isVisible)
            .allowsHitTesting(isVisible)
            .accessibilityHidden(!isVisible)
    }

    private var curve: Animation {
        if reduceMotion { return Motion.narrationDissolveReduced }
        return isVisible ? Motion.narrationDissolveIn : Motion.narrationDissolveOut
    }
}

/// Interpolates `progress` 0...1. Blur envelope `4p(1-p)*peak` is 0 at both
/// rest states and peaks at the mix, so a live ScrollView is never left blurred.
private struct DissolvePlate: ViewModifier, Animatable {
    var progress: Double
    var blurs: Bool

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        if blurs {
            content
                .blur(radius: blurRadius)
                .opacity(progress)
        } else {
            content
                .opacity(progress)
        }
    }

    private var blurRadius: CGFloat {
        CGFloat(4 * progress * (1 - progress)) * Motion.narrationDissolveBlur
    }
}
