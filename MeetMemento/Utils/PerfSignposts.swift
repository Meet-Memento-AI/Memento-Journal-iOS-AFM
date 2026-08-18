//
//  PerfSignposts.swift
//  MeetMemento
//
//  App-stage latency instrumentation (spec 029 R1). OSSignposter intervals
//  render in Instruments alongside the Foundation Models instrument, which
//  remains the only source of token-level prefill/decode attribution
//  (spec 022:268 — no custom timing infrastructure; these are stage markers,
//  not analytics). Signposts are near-free when no trace is attached.
//
//  Privacy: signpost names and metadata never carry message plaintext —
//  stage names and durations only (spec 029 zone declaration).
//

import Foundation
import os

enum PerfSignposts {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.sebastianmendo.MeetMemento"

    /// One turn of chat generation: prep → session → first token → stream.
    static let chatTurn = OSSignposter(subsystem: subsystem, category: "chat.turn")
    /// The narration loop's audio stages: mic stop, TTS activate/first audio,
    /// listen re-arm.
    static let speechLoop = OSSignposter(subsystem: subsystem, category: "speech.loop")
    /// Launch → chat page interactive.
    static let appLoad = OSSignposter(subsystem: subsystem, category: "app.load")

    /// Points-of-interest instance so intervals surface in the default
    /// Instruments track without a custom instrument.
    static let pointsOfInterest = OSSignposter(
        subsystem: subsystem, category: .pointsOfInterest
    )

    /// os.Logger handles for hot paths migrating off the print-based
    /// AppLogger (spec 029 R1). Use `.privacy: .public` only for
    /// non-content metadata.
    static let chatLog = Logger(subsystem: subsystem, category: "chat")
    static let speechLog = Logger(subsystem: subsystem, category: "speech")
    static let perfLog = Logger(subsystem: subsystem, category: "perf")
}
