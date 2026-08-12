//
//  ModelRouter.swift
//  MeetMemento
//
//  Spec 017 R2 / REQ-INT-003: routing is a literal data structure — one table,
//  no scattered conditionals. Pure Swift; no `FoundationModels` import, so the
//  routing decision is unit-testable without a model or a device
//  (CONSTITUTION §4 rule 5).
//

import Foundation

/// What the PCC (Z1) leg can do for a request right now, mirrored
/// SDK-independently so the router stays pure. `QuotaGovernor` produces it.
enum PCCCapability: Equatable, Sendable {
    /// The SDK in use has no PCC type at all (iOS 26). Not a failure — the
    /// baseline. See `RouteReason.sdkUnsupported`.
    case sdkUnsupported
    /// PCC exists and will take the request at full reasoning.
    case available
    /// PCC exists but is unreachable or ineligible right now.
    case unavailable
    /// PCC exists but budget is constrained; this intent must yield
    /// (spec 017 R3's priority order).
    case quotaConstrained
}

/// Why a request ended up where it did. Content-free by construction — this is
/// logged on every generation (CONSTITUTION §4 rule 3).
enum RouteReason: String, Equatable, Sendable {
    /// The row's default zone was used as-is.
    case defaultRoute
    /// The user's Z0 pin (REQ-INT-004) forced on-device.
    case userPinnedToDevice
    /// The row has no Z1 leg; on-device is where it always runs.
    case deviceOnlyIntent
    /// This SDK has no PCC. The Z0 result is the baseline, not a degradation.
    case sdkUnsupported
    /// PCC exists but could not take the request — a real, disclosable fallback.
    case pccUnavailable
    /// PCC exists but budget is constrained and this intent yielded.
    case quotaConstrained
}

/// Priority when budget is constrained (spec 017 R3 / REQ-INT-005): scheduled
/// synthesis outranks interactive chat. A user must never lose their Sunday
/// reflection because they had a long conversation on Saturday.
enum QuotaPriority: Int, Comparable, Sendable {
    case interactive = 0
    case scheduled = 1

    static func < (lhs: QuotaPriority, rhs: QuotaPriority) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// One row of the routing table. `degradedZone == nil` means the intent has no
/// Z1 leg at all — structurally empty, per spec 017 R2's "not 'degrades to
/// itself'" requirement.
struct RoutingRow: Equatable, Sendable {
    let intent: GenerationIntent
    let defaultZone: TrustZone
    let degradedZone: TrustZone?
    let priority: QuotaPriority
}

/// The outcome of routing. `requestedZone` is what the table wanted;
/// `executionZone` is where it will actually run. They differ only on a real
/// fallback, and `wasDegraded` says whether that difference is one the user
/// must be told about (spec 014 R2's disclosure contract).
struct ResolvedRoute: Equatable, Sendable {
    let requestedZone: TrustZone
    let executionZone: TrustZone
    let useDegradedPrompt: Bool
    let wasDegraded: Bool
    let reason: RouteReason
}

enum ModelRouter {
    /// The table. Spec 017 R2 tables nine intents, but `GenerationIntent` has
    /// three — the aspirational rows (entry title/summary/mood/salience/entry
    /// reflection → Z0; weekly `.moderate` and monthly `.deep` → Z1; image
    /// understanding → Z0 with **no** Z1 path, since images are never sent to
    /// PCC per technology/01 §6) arrive with the intents themselves. Adding an
    /// intent without adding a row is a test failure, not a runtime fallback.
    ///
    /// Reasoning levels are a starting hypothesis seeded from technology/02 §5,
    /// to be validated by spec 022's harness — Apple's guidance is "data, not
    /// vibes." Changing one is a one-row edit with a recorded rationale.
    static let table: [RoutingRow] = [
        // Latency matters in conversation and retrieval does the heavy lifting,
        // so ask asks for the cheapest reasoning level rather than the best.
        RoutingRow(intent: .ask,
                   defaultZone: .z1AppleContent(reasoningLevel: .light),
                   degradedZone: .z0Device,
                   priority: .interactive),
        // Summarising a conversation the user just had is mechanical and short;
        // it has never needed more than the on-device model.
        RoutingRow(intent: .summary,
                   defaultZone: .z0Device,
                   degradedZone: nil,
                   priority: .interactive),
        // Onboarding must work in airplane mode on first launch, so the theme
        // estimate is on-device by design, not by fallback.
        RoutingRow(intent: .profileEstimate,
                   defaultZone: .z0Device,
                   degradedZone: nil,
                   priority: .interactive),
    ]

    /// The row for an intent, or `nil` if the table is missing one. Deliberately
    /// optional rather than defaulting to a "closest" row: spec 017 R8 requires
    /// a missing combination be a test failure, and a silent runtime fallback is
    /// exactly the failure mode that rule exists to prevent.
    static func row(for intent: GenerationIntent) -> RoutingRow? {
        table.first { $0.intent == intent }
    }

    /// Pure routing decision.
    ///
    /// `pinnedToDevice` is checked **first**, before any PCC seam is consulted,
    /// so no surface can bypass the user's pin (REQ-INT-004: "a router-level
    /// override, not per-surface logic").
    ///
    /// Degradation honesty (the load-bearing decision here): when the SDK has no
    /// PCC at all, a Z1 row resolves to Z0 as the **baseline** — `wasDegraded`
    /// false, base prompt — because the shipped prompts are authored for the
    /// on-device model and labelling every reply "degraded" would be dishonest,
    /// and would make spec 014 R2's disclosure copy meaningless through
    /// repetition. `wasDegraded` is true only on a live fallback: PCC exists and
    /// could not take this request. That is the case the user is genuinely
    /// getting less than the product normally offers.
    static func resolve(
        intent: GenerationIntent,
        pinnedToDevice: Bool,
        pccCapability: PCCCapability
    ) -> ResolvedRoute {
        guard let row = row(for: intent) else {
            // Unreachable while the exhaustiveness test passes. Fail safe to the
            // most private zone rather than inventing a route.
            return ResolvedRoute(requestedZone: .z0Device, executionZone: .z0Device,
                                 useDegradedPrompt: false, wasDegraded: false,
                                 reason: .deviceOnlyIntent)
        }

        // The pin wins over everything, including the table's default zone.
        if pinnedToDevice {
            return ResolvedRoute(requestedZone: .z0Device, executionZone: .z0Device,
                                 useDegradedPrompt: false, wasDegraded: false,
                                 reason: .userPinnedToDevice)
        }

        // Rows with no Z1 leg never consult the PCC seam at all.
        guard row.defaultZone.carriesContentOffDevice, let fallback = row.degradedZone else {
            return ResolvedRoute(requestedZone: row.defaultZone, executionZone: row.defaultZone,
                                 useDegradedPrompt: false, wasDegraded: false,
                                 reason: .deviceOnlyIntent)
        }

        switch pccCapability {
        case .available:
            return ResolvedRoute(requestedZone: row.defaultZone, executionZone: row.defaultZone,
                                 useDegradedPrompt: false, wasDegraded: false,
                                 reason: .defaultRoute)

        case .sdkUnsupported:
            // Baseline, not degradation — see the doc comment above.
            return ResolvedRoute(requestedZone: fallback, executionZone: fallback,
                                 useDegradedPrompt: false, wasDegraded: false,
                                 reason: .sdkUnsupported)

        case .unavailable:
            return ResolvedRoute(requestedZone: row.defaultZone, executionZone: fallback,
                                 useDegradedPrompt: true, wasDegraded: true,
                                 reason: .pccUnavailable)

        case .quotaConstrained:
            return ResolvedRoute(requestedZone: row.defaultZone, executionZone: fallback,
                                 useDegradedPrompt: true, wasDegraded: true,
                                 reason: .quotaConstrained)
        }
    }
}
