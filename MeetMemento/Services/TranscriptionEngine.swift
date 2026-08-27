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
/// Journal dictation stays progressive; narration uses the transcription
/// preset so punctuation and sentence boundaries land in the live transcript.
enum TranscriptionStyle: Equatable, Sendable {
    /// Composer / journal capture — progressive, volatile captions.
    case dictation
    /// Hands-free narration — transcription preset plus volatile live results.
    case conversation
}
