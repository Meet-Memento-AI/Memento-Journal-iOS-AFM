//
//  ProgressiveBlurEdge.swift
//  MeetMemento
//
//  A translucent blur band for a scroll view's top or bottom edge. Content
//  passes underneath and blurs into the chrome instead of being clipped by it.
//
//  Why this exists, and why it is not `ScrollEdgeFade`:
//  `ScrollEdgeFade` paints a `theme.background` gradient that is fully opaque at
//  the edge. That hides content rather than softening it, and an opaque fill
//  under Liquid Glass makes the glass render as a flat panel (PRES-092). The
//  system's own `scrollEdgeEffectStyle` is not an option either — it draws only
//  where a system bar exists, and this app hides the navigation bar entirely, so
//  it painted a hard white band that sliced entry titles in half. Both root
//  scroll views now set `scrollEdgeEffectHidden(true, for:)` and use this
//  instead.
//
//  Why not `VariableBlur` / `ProgressiveBlurHeader`:
//  those resolve the private `CAFilter` class through a reversed-string lookup
//  (`String("retliFAC".reversed())`) and swap `CABackdropLayer.filters`. It looks
//  better, but the obfuscation is exactly what App Review's static analysis
//  flags under Guideline 2.5.1. Everything here is public API.
//

import SwiftUI

/// A blur band that fades to nothing, for one edge of a scroll view.
///
/// Purely decorative: it has no intrinsic layout footprint at its call sites and
/// never takes hit tests, so adding it cannot move neighbouring chrome.
struct ProgressiveBlurEdge: View {
    enum Edge {
        case top
        case bottom
    }

    let edge: Edge
    /// Total band height. At the top this should reach from the screen edge to
    /// just past the header; at the bottom, past whatever floats there.
    let height: CGFloat
    /// How many masked material layers to stack. See `layerMasks` — this is what
    /// makes the blur *progressive* rather than merely fading.
    var layers: Int = 3

    var body: some View {
        ZStack {
            ForEach(0..<max(1, layers), id: \.self) { index in
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .mask(alignment: .top) { maskGradient(for: index) }
            }
        }
        .frame(height: height)
        .allowsHitTesting(false)
        // Decorative only — VoiceOver must not stop on it, and it must never
        // intercept a scroll or a tap meant for the content beneath.
        .accessibilityHidden(true)
    }

    /// Each successive layer is masked to a *shorter* run than the last, so the
    /// layers overlap most densely at the edge and not at all at the far end.
    ///
    /// This is the trick that buys a real radius ramp out of public API: one
    /// masked material only varies its *opacity* across the band, which reads as
    /// a fade, not a blur. Stacked materials composite — three overlapping at the
    /// edge blur far more than one — so the perceived blur radius ramps down with
    /// the coverage. Apple's own effect varies the radius per pixel; this
    /// approximates it in `layers` discrete steps, which at three is already
    /// smooth enough not to band.
    private func maskGradient(for index: Int) -> some View {
        // Layer 0 spans the whole band, the last spans only the edge-most slice.
        let coverage = 1.0 - (Double(index) / Double(max(1, layers)))
        let opaque = Color.black
        let clear = Color.black.opacity(0)

        return LinearGradient(
            stops: edge == .top
                ? [
                    .init(color: opaque, location: 0),
                    .init(color: opaque, location: coverage * 0.35),
                    .init(color: clear, location: coverage)
                ]
                : [
                    .init(color: clear, location: 1 - coverage),
                    .init(color: opaque, location: 1 - coverage * 0.35),
                    .init(color: opaque, location: 1)
                ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Previews

#Preview("Top edge over content") {
    ZStack(alignment: .top) {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(0..<24, id: \.self) { i in
                    Text("Journal entry line \(i)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.blue.opacity(0.15), in: .rect(cornerRadius: 12))
                }
            }
            .padding()
        }
        ProgressiveBlurEdge(edge: .top, height: 140)
    }
}

#Preview("Bottom edge over content") {
    ZStack(alignment: .bottom) {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(0..<24, id: \.self) { i in
                    Text("Journal entry line \(i)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.orange.opacity(0.15), in: .rect(cornerRadius: 12))
                }
            }
            .padding()
        }
        ProgressiveBlurEdge(edge: .bottom, height: 100)
    }
}
