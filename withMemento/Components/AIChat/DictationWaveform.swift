//
//  DictationWaveform.swift
//  MeetMemento
//
//  Scrolling waveform shown inside ChatInputField while dictating.
//  Figma 431:6079 (ChatInputField / State=Narration).
//

import Combine
import SwiftUI

/// A right-to-left scrolling audio waveform sized to sit inside the 64pt
/// composer capsule.
///
/// **The strip is driven by a clock, not by `audioLevel` changing.** That is the
/// whole trick, and it is not incidental: `SpeechService` smooths the level with
/// a fast one-pole IIR that decays to *exactly* `0.0` after roughly 25 buffers of
/// silence. An earlier version pushed samples from `.onChange(of: audioLevel)`,
/// so once the level hit zero every subsequent publish compared equal, `onChange`
/// stopped firing, and the strip froze — indistinguishable from a crashed view.
/// Sampling on a fixed tick instead means silence scrolls as a flat line, which
/// reads as "listening, hearing nothing", and a genuinely stalled mic is still
/// visible because the pattern goes flat rather than because it stops moving.
///
/// It also replaces `ListeningDotsView`, which pulsed seven fat bars in place —
/// every bar moved together, so a silent room and a loud one looked alike apart
/// from amplitude.
struct DictationWaveform: View {
    /// Live level from `SpeechService`, 0...1.
    var audioLevel: Float

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Newest sample last.
    @State private var samples: [CGFloat] = []
    /// Envelope-followed level, so bars glide instead of flickering.
    @State private var displayLevel: CGFloat = 0

    // MARK: - Design Constants (Figma 431:6084 "SoundWaves")

    private static let barWidth: CGFloat = 3
    private static let barSpacing: CGFloat = 3
    private static let barRadius: CGFloat = 2
    private static let minBarHeight: CGFloat = 6
    private static let maxBarHeight: CGFloat = 30
    private static let containerHeight: CGFloat = 32
    /// Figma varies bar alpha 0.68...1.0 with height; the taller the louder.
    private static let minOpacity: Double = 0.68

    /// One bar plus its trailing gap.
    private static var pitch: CGFloat { barWidth + barSpacing }

    // MARK: - Motion Constants

    /// 20 Hz. At the 6pt bar pitch that scrolls 120pt/s, so the ~213pt strip in
    /// the Figma spec holds about 1.8 seconds of history.
    private static let tick: TimeInterval = 0.05
    /// Asymmetric envelope: jump most of the way up on a transient, fall back
    /// slowly. Symmetric smoothing at this cadence reads as flicker.
    private static let attack: CGFloat = 0.6
    private static let release: CGFloat = 0.15
    /// `SpeechService` publishes `min(1, rms * 3)`, which lands around 0.05–0.45
    /// for normal speech — without this the strip barely leaves the floor.
    private static let gain: CGFloat = 1.8

    private let clock = Timer.publish(every: tick, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            // The trailing gap of the last bar isn't drawn, so add it back
            // before dividing — otherwise the row is one bar short of the space.
            let barCount = max(1, Int((geo.size.width + Self.barSpacing) / Self.pitch))

            HStack(spacing: Self.barSpacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    bar(level: level(at: index, of: barCount))
                }
            }
            .frame(width: geo.size.width, height: Self.containerHeight, alignment: .leading)
            // Glide between ticks. Linear and exactly one tick long, so the
            // motion is continuous rather than a series of visible steps.
            .animation(.linear(duration: Self.tick), value: samples)
            .onAppear {
                // Start full, so no bar is ever drawn from "no sample yet".
                // Without this the left of the strip sat at rest height for the
                // first ~1.8s, reading as a row of dead dots.
                if samples.count < barCount {
                    samples = Array(repeating: 0, count: barCount) + samples
                }
            }
        }
        .frame(height: Self.containerHeight)
        // The bars carry no information VoiceOver can use.
        .accessibilityHidden(true)
        .onReceive(clock) { _ in advance() }
    }

    /// One bar. `level` is 0...1; both the height and the alpha track it, the
    /// way Figma's static mock varies bar opacity 0.68...1.0 with bar height.
    private func bar(level: CGFloat) -> some View {
        let height = Self.minBarHeight + (Self.maxBarHeight - Self.minBarHeight) * level
        let alpha = Self.minOpacity + (1 - Self.minOpacity) * Double(level)
        return RoundedRectangle(cornerRadius: Self.barRadius, style: .continuous)
            .fill(theme.foreground.opacity(alpha))
            .frame(width: Self.barWidth, height: height)
    }

    // MARK: - Sample Buffer

    /// Height factor 0...1 for the bar at `index`, oldest on the left.
    private func level(at index: Int, of barCount: Int) -> CGFloat {
        if reduceMotion {
            // Motion-reduced: no lateral travel, but the bars still answer to
            // the mic. A fixed centre-weighted profile scaled by the current
            // envelope — amplitude without scrolling.
            return displayLevel * shape(at: index, of: barCount)
        }
        let offsetFromEnd = barCount - 1 - index
        let sampleIndex = samples.count - 1 - offsetFromEnd
        guard sampleIndex >= 0, sampleIndex < samples.count else { return 0 }
        return samples[sampleIndex]
    }

    /// Centre-weighted profile, so a motion-reduced strip still looks like a
    /// level meter rather than a solid block.
    private func shape(at index: Int, of barCount: Int) -> CGFloat {
        guard barCount > 1 else { return 1 }
        let centre = CGFloat(barCount - 1) / 2
        let distance = abs(CGFloat(index) - centre) / centre
        return 1 - distance * 0.55
    }

    /// One tick: follow the level, then shift the strip left by one bar.
    ///
    /// Runs unconditionally — pushing on every tick regardless of whether
    /// `audioLevel` moved is what keeps the strip alive through silence.
    private func advance() {
        let target = min(1, max(0, CGFloat(audioLevel) * Self.gain))
        let coefficient = target > displayLevel ? Self.attack : Self.release
        displayLevel += (target - displayLevel) * coefficient

        // Reduce Motion reads `displayLevel` directly and never scrolls, so
        // there is no buffer to maintain.
        guard !reduceMotion else { return }

        samples.append(displayLevel)
        // Cap at the widest strip any device will render.
        if samples.count > 128 {
            samples.removeFirst(samples.count - 128)
        }
    }
}

// MARK: - Previews

#Preview("Dictation Waveform - Live") {
    DictationWaveformPreview()
        .padding()
        .useTheme()
}

#Preview("Dictation Waveform - Dark") {
    DictationWaveformPreview()
        .padding()
        .useTheme()
        .preferredColorScheme(.dark)
}

// No Reduce Motion preview: `accessibilityReduceMotion` is a read-only
// environment value, so it can't be injected here — toggle it in the simulator
// (Settings › Accessibility › Motion) to check the in-place behaviour.

private struct DictationWaveformPreview: View {
    @State private var audioLevel: Float = 0
    @State private var timer: Timer?

    var body: some View {
        DictationWaveform(audioLevel: audioLevel)
            .onAppear {
                // Rough stand-in for speech: bursts of level with gaps between.
                var phase = 0
                timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
                    phase += 1
                    audioLevel = (phase % 40) < 28 ? Float.random(in: 0.05...0.45) : 0
                }
            }
            .onDisappear {
                timer?.invalidate()
                timer = nil
            }
    }
}
