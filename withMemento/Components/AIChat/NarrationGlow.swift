//
//  NarrationGlow.swift
//  MeetMemento
//
//  Bottom "voice shadow" (Figma 302:619) for Chat's narration mode.
//

import Combine
import SwiftUI

/// An 880×440 blurred gradient anchored past the bottom edge whose silhouette
/// is the voice — a traveling multi-sine wave, lifted by the mic while the
/// user speaks and by a slow breath while Memento thinks/speaks.
///
/// One brown silhouette, blurred, composited straight onto the page fill.
/// Entrance is a rise from fully below the fold at full opacity, not a fade
/// shared with the thread dissolve. Reduce Motion (PRES-094) skips the rise
/// and cross-fades opacity only.
///
/// Driven by a 20 Hz clock, NOT `.onChange(of: audioLevel)` — SpeechService's
/// smoothed level decays to exactly 0 in silence and stops publishing changes.
struct NarrationGlow: View {
    /// False while Chat is in the typing composer — the glow stays mounted
    /// so it can rise in and out, rather than popping on `if`.
    var isActive: Bool
    var audioLevel: Float
    /// True while TTS speaks/thinks: ignore the (dead) mic level and roll.
    var isAutonomous: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var displayLevel: Double = 0
    @State private var samples: [Double] = []
    @State private var breathPhase: Double = 0
    /// Opacity latch: on for the whole rise, held through the exit slide,
    /// then dropped once the silhouette is off-screen. Reduce Motion uses
    /// `isActive` directly instead.
    @State private var isDrawn: Bool = false

    private static let tick: TimeInterval = 0.05
    private static let attack: Double = 0.6
    private static let release: Double = 0.15
    /// Speech RMS is typically 0.05–0.45 after SpeechService's `* 3`; this
    /// gain makes spoken syllables occupy most of the wave's height.
    private static let gain: Double = 2.6
    private static let pointCount = 48
    /// Soft enough to read as a wash, sharp enough that the crest still moves.
    private static let waveBlur: CGFloat = 64
    /// Decelerating rise from below the fold. Content plates dissolve on
    /// `Motion.narrationDissolve*` instead — never share a `withAnimation`
    /// with this offset, or the rise reads as a fade.
    private static let riseDuration: TimeInterval = 0.7

    /// Sits just past the bottom edge so the bloom reads as a floor wash.
    private static let restingOffset: CGFloat = 40
    /// Frame height + former blur + slack so the blurred rect starts off-screen.
    private static let hiddenOffset: CGFloat = 560

    private var gradient: LinearGradient {
        LinearGradient(
            colors: [PrimaryScale.primary600, PrimaryScale.primary700],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var waveOpacity: Double {
        if reduceMotion { return isActive ? 0.50 : 0 }
        // Visible the whole time it is on-screen, including the exit slide.
        if isActive { return 0.50 }
        return isDrawn ? 0.50 : 0
    }

    private var glowOffset: CGFloat {
        if reduceMotion { return Self.restingOffset }
        return isActive ? Self.restingOffset : Self.hiddenOffset
    }

    private var opacityAnimation: Animation? {
        reduceMotion ? Motion.narrationDissolveReduced : nil
    }

    private var offsetAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: Self.riseDuration)
    }

    private let clock = Timer.publish(every: tick, on: .main, in: .common).autoconnect()

    var body: some View {
        silhouette
            .frame(width: 880, height: 440)
            .blur(radius: Self.waveBlur)
            .offset(y: glowOffset)
            .animation(offsetAnimation, value: isActive)
            .opacity(waveOpacity)
            .animation(opacityAnimation, value: reduceMotion ? isActive : isDrawn)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .animation(.linear(duration: Self.tick), value: samples)
            .onReceive(clock) { _ in advance() }
            .onAppear {
                seedSamplesIfNeeded()
                if isActive { isDrawn = true }
            }
            .onChange(of: isActive) { _, active in
                handleActiveChange(active)
            }
    }

    @ViewBuilder
    private var silhouette: some View {
        if reduceMotion {
            Ellipse()
                .fill(gradient)
        } else {
            NarrationWaveShape(points: AnimatableCurve(values: samples))
                .fill(gradient)
        }
    }

    private func handleActiveChange(_ active: Bool) {
        guard !reduceMotion else {
            isDrawn = active
            return
        }
        if active {
            isDrawn = true
        } else {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(Self.riseDuration))
                if !isActive { isDrawn = false }
            }
        }
    }

    private func seedSamplesIfNeeded() {
        if samples.count != Self.pointCount {
            samples = travelingWave(at: breathPhase, lift: displayLevel)
        }
    }

    private func advance() {
        breathPhase += Self.tick

        let target: Double
        if isAutonomous {
            target = 0.40 + 0.32 * sin(breathPhase * 2 * .pi * 0.2)
        } else if isActive {
            target = min(1, max(0, Double(audioLevel) * Self.gain))
        } else {
            target = 0
        }
        let coefficient = target > displayLevel ? Self.attack : Self.release
        displayLevel += (target - displayLevel) * coefficient

        guard !reduceMotion else { return }
        samples = travelingWave(at: breathPhase, lift: displayLevel)
    }

    /// Idle traveling sines, scaled up when the mic or autonomous breath lifts.
    private func travelingWave(at time: Double, lift: Double) -> [Double] {
        let amplitude = 0.72 + 0.28 * min(1, max(0, lift))
        return (0..<Self.pointCount).map { index in
            let x = Double(index) / Double(Self.pointCount - 1)
            let idle =
                0.45
                + 0.22 * sin(2 * .pi * (x * 1.2 + time * 0.45))
                + 0.14 * sin(2 * .pi * (x * 2.4 - time * 0.70))
                + 0.10 * sin(2 * .pi * (x * 0.6 + time * 0.15))
            return min(1, max(0, idle * amplitude))
        }
    }
}

private struct NarrationWaveShape: Shape {
    var points: AnimatableCurve

    var animatableData: AnimatableCurve {
        get { points }
        set { points = newValue }
    }

    private static let restFraction: CGFloat = 0.48
    private static let peakFraction: CGFloat = 0.95

    func path(in rect: CGRect) -> Path {
        let values = points.values
        guard values.count > 1, rect.width > 0, rect.height > 0 else {
            return Path(ellipseIn: rect)
        }

        let count = values.count
        func point(at index: Int) -> CGPoint {
            let progress = CGFloat(index) / CGFloat(count - 1)
            let taper = sin(.pi * progress)
            let level = CGFloat(min(1, max(0, values[index])))
            let fraction = taper * (Self.restFraction + (Self.peakFraction - Self.restFraction) * level)
            return CGPoint(
                x: rect.minX + rect.width * progress,
                y: rect.maxY - rect.height * fraction
            )
        }

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        var previous = point(at: 0)
        path.addLine(to: previous)
        for index in 1..<count {
            let current = point(at: index)
            let mid = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
            path.addQuadCurve(to: mid, control: previous)
            previous = current
        }
        path.addLine(to: previous)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct AnimatableCurve: VectorArithmetic, Equatable {
    var values: [Double]

    static var zero: AnimatableCurve { AnimatableCurve(values: []) }

    static func + (lhs: AnimatableCurve, rhs: AnimatableCurve) -> AnimatableCurve {
        merge(lhs, rhs, +)
    }

    static func - (lhs: AnimatableCurve, rhs: AnimatableCurve) -> AnimatableCurve {
        merge(lhs, rhs, -)
    }

    mutating func scale(by rhs: Double) {
        values = values.map { $0 * rhs }
    }

    var magnitudeSquared: Double {
        values.reduce(0) { $0 + $1 * $1 }
    }

    private static func merge(
        _ lhs: AnimatableCurve,
        _ rhs: AnimatableCurve,
        _ combine: (Double, Double) -> Double
    ) -> AnimatableCurve {
        let count = max(lhs.values.count, rhs.values.count)
        var out = [Double](repeating: 0, count: count)
        for index in 0..<count {
            let a = index < lhs.values.count ? lhs.values[index] : 0
            let b = index < rhs.values.count ? rhs.values[index] : 0
            out[index] = combine(a, b)
        }
        return AnimatableCurve(values: out)
    }
}
