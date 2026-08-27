//
//  TranscriptionEngine.swift
//  MeetMemento
//
//  Spec 018 R1: capture seam. SpeechService keeps the published UI surface;
//  the engine behind it is SpeechAnalyzer / SpeechTranscriber / SpeechDetector.
//

import Foundation

enum TranscriptionUpdate: Equatable, Sendable {
    case volatile(String)
    case finalized(String)
}

enum TranscriptionAssetState: Equatable, Sendable {
    case installed, downloading, missing, unsupported
}

/// How the on-device transcriber is configured for this session.
/// Both styles use progressive + fastResults for live captions; they differ
/// in session lifetime (dictation finishes on stop; conversation pauses).
enum TranscriptionStyle: Equatable, Sendable {
    /// Composer / journal capture — progressive, volatile captions.
    case dictation
    /// Hands-free narration — same live-caption transcriber; analyzer stays warm.
    case conversation
}
