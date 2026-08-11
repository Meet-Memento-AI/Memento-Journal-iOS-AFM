//
//  TrustZone.swift
//  MeetMemento
//
//  The canonical trust-zone contract (spec 014 R1 / REQ-PRIV-001). An enum —
//  not a Bool or a string — so the compiler enforces that every generation
//  request declares where it runs, and every persisted artifact records where
//  it actually ran.
//
//  There is deliberately NO `.z2` case: a type that could represent
//  Z2-tagged journal content would itself be a way to violate REQ-PRIV-001
//  (no journal content, transcript, reflection, embedding, tag, mood value,
//  or content-derived metadata may cross to third-party infrastructure —
//  CONSTITUTION §4 rule 8).
//
//  No `import FoundationModels` — pure Swift.
//

import Foundation

/// How hard Private Cloud Compute should reason for a Z1 request (spec 014 R1).
/// The level rides on the zone value so spec 017 R2's router emits one value
/// that answers both "where" and "how hard". The SDK's `.custom(String)` case
/// is intentionally NOT represented here (technology/02 §5: handle it in the
/// boundary's exhaustive switches, never expose it in the router's column type).
enum PCCReasoningLevel: String, Codable, Sendable, Equatable, CaseIterable {
    case light
    case moderate
    case deep
}

/// Where a generation runs (spec 014 R1's four-state contract, three cases —
/// reasoning level is an associated value, not a separate field).
///
/// - `z0Device`: never leaves the device; works in airplane mode.
///   Transcription, retrieval, search, entry-level generation, TTS.
/// - `z1AppleContent`: Apple attested infrastructure (Private Cloud Compute)
///   carrying journal content — weekly/monthly synthesis, chat.
/// - `z1AppleContentFree`: Apple infrastructure carrying NO journal content
///   (e.g. WeatherKit: a location, never entry text). Deliberately distinct —
///   collapsing it into `.z0Device` or `.z1AppleContent` misrepresents it
///   either way. Content-free Z1 calls are not `GenerationRequest`s.
///
/// Rules (spec 014 R1):
/// - Every `GenerationRequest` carries its zone set BEFORE the call, never
///   inferred after.
/// - Every outcome persists the zone it ACTUALLY ran in, which may differ
///   from the requested zone after degradation.
enum TrustZone: Sendable, Equatable, Hashable, Codable {
    case z0Device
    case z1AppleContent(reasoningLevel: PCCReasoningLevel)
    case z1AppleContentFree

    /// True for any zone that would carry journal content off-device.
    var carriesContentOffDevice: Bool {
        if case .z1AppleContent = self { return true }
        return false
    }

    /// Stable identifier for logging/persistence display (never journal content).
    var identifier: String {
        switch self {
        case .z0Device:
            return "z0-device"
        case .z1AppleContent(let level):
            return "z1-apple-content-\(level.rawValue)"
        case .z1AppleContentFree:
            return "z1-apple-content-free"
        }
    }
}
