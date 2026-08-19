//
//  VoiceCatalog.swift
//  MeetMemento
//
//  The four neural voices, and the only place they are defined (spec 033 R1).
//  Adding, removing or reordering a voice is an edit to this file and nowhere
//  else — no branching in views, no per-voice code anywhere.
//
//  The roster is fixed at four by owner decision (DEC-011 / DEC-012): F1, F2,
//  M1, M3. The base model publishes ten style vectors; the other six are never
//  vendored into the repository (spec 030 R4), so the roster is enforced by
//  absence rather than by a filter someone can later widen.
//
//  Style ids are INTERNAL. They never appear in the UI — spec 033 R5 presents
//  voices by character, not by gender, because a journaling companion is chosen
//  by how it feels to be spoken to.
//

import Foundation

/// One selectable voice. Backed by a bundled style vector; the model itself is
/// shared across all four (a voice is data, not a model).
struct VoiceOption: Identifiable, Equatable, Hashable {
    /// Internal style id — matches the bundled `<id>.json` style vector.
    /// Never rendered. See spec 033 R5.
    let id: String

    /// Character-led display name, e.g. "Warm".
    let displayName: String

    /// One line of character. Not a demographic description.
    let descriptor: String

    /// SF Symbol for the row.
    let symbol: String
}

enum VoiceCatalog {

    // MARK: - The roster

    /// Exactly four voices. See the file header before changing this.
    ///
    /// ⚠️ **Descriptors below are PROVISIONAL.** There is no published
    /// characterisation of these voices anywhere — the upstream style JSONs
    /// carry only provenance (source file, sample rate), and the named samples
    /// in the model card (Nora, Luna, Keld…) are Voice Builder customs, not
    /// these presets. Real descriptors can only be chosen by listening, which
    /// happens in the V30 audition (spec 033 R7). Until then these are
    /// placeholders and must not be treated as decided copy.
    static let all: [VoiceOption] = [
        VoiceOption(
            id: "F1",
            displayName: "Warm",
            descriptor: "Even and unhurried",
            symbol: "waveform"
        ),
        VoiceOption(
            id: "F2",
            displayName: "Bright",
            descriptor: "Lighter, with more lift",
            symbol: "waveform"
        ),
        VoiceOption(
            id: "M1",
            displayName: "Measured",
            descriptor: "Deliberate and grounded",
            symbol: "waveform"
        ),
        VoiceOption(
            id: "M3",
            displayName: "Steady",
            descriptor: "Low and level",
            symbol: "waveform"
        )
    ]

    /// The voice a user gets when they have never chosen one, and the
    /// resolution target for anything unrecognised.
    static let `default`: VoiceOption = all[0]

    // MARK: - Resolution

    /// Resolves a persisted identifier to a voice, **silently**.
    ///
    /// Three cases all land on `default`, and none of them surfaces an error
    /// (spec 033 R3):
    ///
    /// 1. A legacy `AVSpeechSynthesisVoice.identifier` — every existing user who
    ///    ever picked a voice has one of these persisted
    ///    (e.g. `com.apple.voice.enhanced.en-US.Evan`).
    /// 2. `nil` — the old "Automatic" selection, which no longer exists.
    /// 3. A style id retired by a future roster change.
    ///
    /// The user picked a voice once; they get a good voice now. Explaining a
    /// migration they did not ask for is worse than performing it quietly.
    static func resolve(persistedID: String?) -> VoiceOption {
        guard let persistedID,
              let match = all.first(where: { $0.id == persistedID })
        else { return `default` }
        return match
    }

    /// True when the persisted value names a voice this build actually ships.
    /// Used by tests and by migration to tell "already valid" from "resolved".
    static func isKnown(_ persistedID: String?) -> Bool {
        guard let persistedID else { return false }
        return all.contains { $0.id == persistedID }
    }
}
