//
//  EvidenceState.swift
//  MeetMemento
//
//  How much of the journal this turn may use. Decided by code, before the
//  model writes. No Foundation Models import.
//

import Foundation

/// `.none` — the archive has no entries.
/// `.ambient` — entries exist, and retrieval did not find a topical match.
/// `.matched` — retrieval found entries this turn may cite.
enum EvidenceState: String, Sendable, Equatable {
    case none
    case ambient
    case matched
}
