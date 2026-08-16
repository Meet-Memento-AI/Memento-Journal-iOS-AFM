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
        case .normal: return "The system reading speed"
        case .brisk: return "Natural conversational pace"
        case .fast: return "Quick review"
        }
    }

    /// Matches a stored raw rate back to a preset row (float round-trips
    /// through UserDefaults exactly, but be tolerant anyway).
    static func nearest(to rate: Float) -> SpeechRatePreset {
        allCases.min { abs($0.rawValue - rate) < abs($1.rawValue - rate) } ?? .brisk
    }
}
