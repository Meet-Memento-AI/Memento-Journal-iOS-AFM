//
//  SpeechRatePreset.swift
//  MeetMemento
//
//  Named speaking-rate presets for read-aloud (spec 018 R7). Discrete rows
//  rather than a slider: consistent with the hand-built settings cards and
//  friendlier to VoiceOver.
//

import Foundation

enum SpeechRatePreset: Float, CaseIterable, Identifiable {
    case slower = 0.45
    case normal = 0.50
    /// The tuned value the feature shipped with — slightly above the system
    /// default 0.5, which reads slow for conversational AI.
    case brisk = 0.53
    case fast = 0.58

    var id: Float { rawValue }

    var displayName: String {
        switch self {
        case .slower: return "Slower"
        case .normal: return "Normal"
        case .brisk: return "Brisk"
        case .fast: return "Fast"
        }
    }

    var subtitle: String {
        switch self {
        case .slower: return "Relaxed, easy to follow"
        case .normal: return "The model's natural pace"
        case .brisk: return "Natural conversational pace"
        case .fast: return "Quick review"
        }
    }

    /// The same preset expressed for the neural engine (`SupertonicOptions.speed`).
    ///
    /// `rawValue` above is an `AVSpeechUtteranceRate` and stays that way — it is
    /// what `PreferencesService.speechRate` persists, and the fallback path still
    /// speaks in that scale. This is the translation, not a replacement.
    ///
    /// Both scales normalise to "1x = the engine's default", but the defaults
    /// differ: AVSpeech's is 0.5, Supertonic's is 1.0. So the conversion is
    /// `rawValue / 0.5`, which is where these numbers come from. Written out
    /// case by case rather than as arithmetic so they can be tuned by ear
    /// without the derivation pretending to still hold.
    ///
    /// Note `.brisk` lands on 1.06, within a rounding error of the model's own
    /// 1.05 default — so the shipping default preserves the voices as auditioned.
    ///
    /// Supertonic applies this as `duration /= speed` against the
    /// DurationPredictor's output, so the model genuinely re-synthesises at the
    /// new pace. It is not resampling, and the pitch does not shift.
    var neuralSpeed: Float {
        switch self {
        case .slower: return 0.90
        case .normal: return 1.00
        case .brisk: return 1.06
        case .fast: return 1.16
        }
    }

    /// Matches a stored raw rate back to a preset row (float round-trips
    /// through UserDefaults exactly, but be tolerant anyway).
    static func nearest(to rate: Float) -> SpeechRatePreset {
        allCases.min { abs($0.rawValue - rate) < abs($1.rawValue - rate) } ?? .brisk
    }
}
