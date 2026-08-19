//
//  SupertonicEngineDeviceTests.swift
//  MeetMementoTests
//
//  MEASURE-ON-DEVICE — proves the bundled neural voice actually loads and
//  synthesizes on real hardware (spec 030 R2 acceptance, spec 031).
//
//  These are deliberately NOT part of the fast unit suite's contract: they load
//  ~148 MB of CoreML graphs and run real inference. On the simulator there is no
//  Neural Engine, so timings here are meaningless — the numbers only mean
//  something on a physical device. They are skipped when the assets are absent
//  so a simulator run does not report a false failure.
//

import AVFoundation
import XCTest
@testable import MeetMemento

final class SupertonicEngineDeviceTests: XCTestCase {

    /// Every asset the engine needs is actually in the built bundle.
    /// This is the check that catches a resource that silently stopped shipping.
    func test_voicePack_isCompleteInBundle() throws {
        XCTAssertTrue(
            VoicePack.isComplete,
            "voice pack incomplete — missing: \(VoicePack.missingAssets().joined(separator: ", "))"
        )
    }

    /// Exactly four style vectors ship — the roster is enforced by which files
    /// are vendored at all (spec 030 R4), not by a filter.
    func test_exactlyFourVoicesShip() throws {
        try XCTSkipUnless(VoicePack.isComplete, "voice assets not in this build")
        let styles = VoicePack.styleURLs()
        XCTAssertEqual(styles.count, 4)
        XCTAssertEqual(Set(styles.keys), ["F1", "F2", "M1", "M3"])
    }

    /// The pipeline end-to-end: load four CoreML graphs, tokenize, run
    /// flow-matching, vocode, and produce non-silent audio.
    ///
    /// This is the assumption that was reasoned about for several sessions and
    /// never proven — that a pre-compiled `.mlmodelc` vendored into the bundle
    /// loads and runs.
    func test_synthesize_producesAudibleAudio() async throws {
        try XCTSkipUnless(VoicePack.isComplete, "voice assets not in this build")

        let engine = SupertonicEngine.shared
        try await engine.prepare()

        let buffer = try await engine.synthesize(
            text: "This is how I'll sound when I read your journal back to you.",
            styleID: "F1"
        )

        XCTAssertEqual(buffer.format.sampleRate, 44_100, "Supertonic renders at 44.1 kHz")
        XCTAssertGreaterThan(buffer.frameLength, 0, "no audio produced")

        // Non-silent: a buffer of zeros would satisfy every check above while
        // being completely useless, which is exactly the failure worth catching.
        let peak = Self.peakAmplitude(of: buffer)
        XCTAssertGreaterThan(peak, 0.01, "output is silent (peak \(peak))")
    }

    /// All four voices render, and they are not the same audio — a roster where
    /// every row sounds identical is the specific failure this whole change
    /// exists to avoid.
    func test_allFourVoices_renderAndDiffer() async throws {
        try XCTSkipUnless(VoicePack.isComplete, "voice assets not in this build")

        let engine = SupertonicEngine.shared
        var fingerprints: [String: Float] = [:]

        for voice in VoiceCatalog.all {
            let buffer = try await engine.synthesize(text: "Hello.", styleID: voice.id)
            XCTAssertGreaterThan(buffer.frameLength, 0, "\(voice.id) produced no audio")
            fingerprints[voice.id] = Self.peakAmplitude(of: buffer)
        }

        XCTAssertEqual(fingerprints.count, 4)
        XCTAssertGreaterThan(
            Set(fingerprints.values.map { ($0 * 10_000).rounded() }).count, 1,
            "all four voices produced identical output — styles are not being applied"
        )
    }

    /// Warm-up is idempotent (spec 031 R3): a second `prepare()` must not reload.
    func test_prepare_isIdempotentAndFast() async throws {
        try XCTSkipUnless(VoicePack.isComplete, "voice assets not in this build")

        let engine = SupertonicEngine.shared
        try await engine.prepare()

        let start = CFAbsoluteTimeGetCurrent()
        try await engine.prepare()
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

        XCTAssertLessThan(elapsed, 5.0, "second prepare() took \(elapsed) ms — expected a no-op")
    }

    /// MEASURE-ON-DEVICE: real-time factor. Meaningless on the simulator (no ANE)
    /// — recorded rather than asserted, and read from the test log.
    func test_measure_realTimeFactor() async throws {
        try XCTSkipUnless(VoicePack.isComplete, "voice assets not in this build")

        let engine = SupertonicEngine.shared
        try await engine.prepare()

        let text = "The weather turned today, and I noticed I felt lighter walking home."
        let start = CFAbsoluteTimeGetCurrent()
        let buffer = try await engine.synthesize(text: text, styleID: "F1")
        let wall = CFAbsoluteTimeGetCurrent() - start

        let audioSeconds = Double(buffer.frameLength) / buffer.format.sampleRate
        let rtf = wall / max(audioSeconds, 0.0001)
        print("MEASURE-ON-DEVICE rtf=\(String(format: "%.3f", rtf)) " +
              "wall=\(String(format: "%.3f", wall))s audio=\(String(format: "%.3f", audioSeconds))s")
        XCTAssertGreaterThan(audioSeconds, 0)
    }

    /// Speed actually reaches the model. `SupertonicOptions.speed` divides the
    /// DurationPredictor's output, so a slower rate must produce *more* samples
    /// for identical text — the check that catches the parameter being accepted
    /// and then quietly dropped, which is indistinguishable by ear from a rate
    /// that simply does not do much.
    func test_speed_changesRenderedLength() async throws {
        try XCTSkipUnless(VoicePack.isComplete, "voice assets not in this build")

        let engine = SupertonicEngine.shared
        let text = "The weather turned today, and I noticed I felt lighter walking home."

        let slow = try await engine.synthesize(
            text: text, styleID: "F1", speed: SpeechRatePreset.slower.neuralSpeed)
        let fast = try await engine.synthesize(
            text: text, styleID: "F1", speed: SpeechRatePreset.fast.neuralSpeed)

        XCTAssertGreaterThan(
            slow.frameLength, fast.frameLength,
            "slower must render more audio than faster for the same text "
            + "(slow \(slow.frameLength) vs fast \(fast.frameLength))"
        )
    }

    // MARK: - Helpers

    private static func peakAmplitude(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        var peak: Float = 0
        for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(channel[i])) }
        return peak
    }
}
