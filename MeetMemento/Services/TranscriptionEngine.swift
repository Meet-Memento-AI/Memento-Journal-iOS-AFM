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
