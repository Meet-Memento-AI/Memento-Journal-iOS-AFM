//
//  EvidenceState.swift
//  withMemento
//
//  How much of the journal this turn may use. Decided by code, before the
//  model writes. No Foundation Models import.
//
//  Two decisions read this vocabulary. The turn gate (spec 046 R3) picks the
//  channel: `.none` there means the archive is empty. The `EvidencePack`
//  (spec 050) records what the prompt actually carries after retrieval and
//  stance: `.none` there means nothing quotable this turn. The pack's state
//  is never higher than the turn's.
//

import Foundation

/// `.none` — nothing to use: an empty archive at the turn gate; a miss, an
///   empty retrieval, or a non-retrieving channel in the pack.
/// `.ambient` — entries exist, and retrieval did not find a topical match.
/// `.matched` — retrieval found entries this turn may cite.
enum EvidenceState: String, Sendable, Equatable {
    case none
    case ambient
    case matched
}
