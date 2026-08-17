//
//  NarrationGlow.swift
//  MeetMemento
//
//  Bottom "voice shadow" (Figma 302:619) for Chat's narration mode.
//

import Combine
import SwiftUI

/// A 440×220 blurred gradient anchored past the bottom edge whose silhouette
/// is the voice — a scrolling ring buffer of envelope samples shapes the
/// glow's top edge. While Memento thinks/speaks the buffer is fed a slow sine
/// instead, so the wave stays alive without a live mic.
///
/// Driven by a 20 Hz clock, NOT `.onChange(of: audioLevel)` — SpeechService's
/// smoothed level decays to exactly 0 in silence and stops publishing changes.
struct NarrationGlow: View {
    var audioLevel: Float
    /// True while TTS speaks/thinks: ignore the (dead) mic level and roll.
    var isAutonomous: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var displayLevel: Double = 0
    @State private var samples: [Double] = []
    @State private var breathPhase: Double = 0

    private static let tick: TimeInterval = 0.05
    private static let attack: Double = 0.6
    private static let release: Double = 0.15
    private static let gain: Double = 1.8
    private static let pointCount = 48

    private var baseOpacity: Double { colorScheme == .dark ? 0.30 : 0.40 }

    private var gradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: "#7B5239"), Color(hex: "#5E4E42")],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private let clock = Timer.publish(every: tick, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if reduceMotion {
                Ellipse()
                    .fill(gradient)
            } else {
                NarrationWaveShape(points: AnimatableCurve(values: samples))
                    .fill(gradient)
            }
        }
        .frame(width: 440, height: 220)
        .blur(radius: 50)
        .opacity(baseOpacity + 0.35 * displayLevel)
        .drawingGroup()
        .offset(y: 80)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(.linear(duration: Self.tick), value: samples)
        .animation(.linear(duration: Self.tick), value: displayLevel)
        .onReceive(clock) { _ in advance() }
        .onAppear {
            if samples.count < Self.pointCount {
                samples = Array(repeating: 0, count: Self.pointCount - samples.count) + samples
            }
        }
    }

    private func advance() {
        let target: Double
        if isAutonomous {
            breathPhase += Self.tick
            target = 0.3 + 0.15 * sin(breathPhase * 2 * .pi * 0.2)
        } else {
            target = min(1, max(0, Double(audioLevel) * Self.gain))
        }
        let coefficient = target > displayLevel ? Self.attack : Self.release
        displayLevel += (target - displayLevel) * coefficient

        guard !reduceMotion else { return }

        samples.append(displayLevel)
        if samples.count > Self.pointCount {
            samples.removeFirst(samples.count - Self.pointCount)
        }
    }
}

private struct NarrationWaveShape: Shape {
    var points: AnimatableCurve

    var animatableData: AnimatableCurve {
        get { points }
        set { points = newValue }
    }

    private static let restFraction: CGFloat = 0.35
    private static let peakFraction: CGFloat = 0.85

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
