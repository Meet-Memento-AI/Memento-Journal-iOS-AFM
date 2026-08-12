//
//  TrustZone.swift
//  MeetMemento
//
//  Spec 014 R1's canonical trust-boundary contract, adopted verbatim. This file
//  is pure Swift on purpose: it is the vocabulary every other module uses to
//  talk about where a generation ran, so it must never depend on
//  `FoundationModels` (CONSTITUTION §4 rule 5 / REQ-INT-001).
//
//  Spec 017 R1 reconciles the architecture spec's older two-case sketch
//  (`enum TrustZone { case device, apple }`) against this enum: the reasoning
//  level rides on the zone value, so the router emits one value answering both
//  "where" and "how hard".
//

import Foundation

/// The innermost zone an operation required, per architecture spec §3.2.
/// There is no `.z2` case: REQ-PRIV-001 requires content never cross into
/// Z2 under any configuration, so a type that could represent Z2-tagged
/// content would itself be a way to violate that rule. Z2 (RevenueCat
/// receipts + anonymous ID only, spec 021) never carries anything this
/// enum tags.
enum TrustZone: Equatable, Hashable, Codable, Sendable {
    /// Never leaves the device. Works in airplane mode. Transcription,
    /// entry reflection, mood/tag inference, retrieval, search, TTS.
    case z0Device

    /// Leaves the device to Apple's attested infrastructure, carrying
    /// journal content. PCC generation: weekly, monthly, chat.
    case z1AppleContent(reasoningLevel: PCCReasoningLevel)

    /// Leaves the device to Apple's infrastructure but carries **no**
    /// journal content — e.g. WeatherKit (a location, never entry text).
    /// Distinct from `.z1AppleContent` because REQ-PRIV-001's guarantee is
    /// about content specifically; collapsing this into either `.z0Device`
    /// (false — it's a real network call) or `.z1AppleContent` (false —
    /// implies content exposure that never happens) would misrepresent it
    /// either way. `technology/08-context-frameworks.md` §4 is the concrete
    /// case this exists for.
    case z1AppleContentFree
}

/// PCC reasoning levels (`technology/02` §5).
///
/// Deliberately three cases, not four. The SDK's
/// `ContextOptions.ReasoningLevel` also has `.custom(String)` — "a level not
/// supported by the other cases" — but `technology/02` §5 is explicit that the
/// routing table has no use for it and it must not appear in the router's
/// column type. Keeping it out means an exhaustive switch here can never be
/// destabilized by a value the table cannot express.
enum PCCReasoningLevel: String, Codable, Sendable, CaseIterable {
    case light, moderate, deep
}

extension TrustZone {
    /// Whether journal content leaves the device for this zone. This is the
    /// REQ-PRIV-001 question, and it is deliberately *not* "is this a network
    /// call" — `.z1AppleContentFree` is a real network call that carries no
    /// content, and conflating the two is exactly what this enum exists to
    /// prevent.
    var carriesContentOffDevice: Bool {
        switch self {
        case .z0Device, .z1AppleContentFree: return false
        case .z1AppleContent: return true
        }
    }

    /// Stable, content-free identifier for logging and persisted provenance
    /// (`REQ-PRM-004`). Stable across releases — a quality study that cannot
    /// join on this string is worthless, so treat these as a wire format.
    var identifier: String {
        switch self {
        case .z0Device: return "z0.device"
        case .z1AppleContent(let level): return "z1.apple.content.\(level.rawValue)"
        case .z1AppleContentFree: return "z1.apple.content-free"
        }
    }
}
