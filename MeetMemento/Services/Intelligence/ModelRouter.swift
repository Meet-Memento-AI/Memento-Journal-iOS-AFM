//
//  ModelRouter.swift
//  MeetMemento
//
//  Table-driven Z0/Z1 routing (spec 017 R2 / REQ-INT-003). Routing is a
//  literal data structure — one row per `GenerationIntent`, no scattered
//  conditionals. The exhaustiveness test (ModelRouterTests) breaks the build
//  when an intent is added without a row.
//
//  Honest-degradation semantics on the iOS 26 SDK: `PrivateCloudComputeLanguageModel`
//  does not exist in this SDK, so a Z1-default row resolves to `.z0Device` as
//  the BASELINE (`wasDegraded == false`, base prompt) — the shipped prompts
//  are authored for the on-device model, and labeling every reply "degraded"
//  would be dishonest. `wasDegraded == true` + the degraded prompt variant
//  (REQ-INT-010) fire only on a LIVE fallback — PCC advertised but
//  unavailable/quota-constrained — which activates automatically when the
//  iOS 27 provider lands, and is fully unit-tested today via the capability
//  input.
//
//  The user's Z0-pin (REQ-INT-004) is a router-level override: it short-
//  circuits BEFORE any PCC seam is consulted, so no surface can escape it.
//
//  No `import FoundationModels` — pure Swift.
//

import Foundation

/// Quota priority class for spec 017 R3's fixed ordering
/// (weekly > monthly > chat): scheduled synthesis outranks interactive chat —
/// "the user must never lose their Sunday reflection because they had a long
/// conversation on Saturday."
enum QuotaPriority: Sendable, Equatable {
    /// Background/scheduled synthesis (future weekly/monthly reflections).
    case scheduled
    /// User-facing interactive generation (chat). Degrades to Z0 first when
    /// quota approaches the limit.
    case interactive
}

/// What the PCC seam reports about Private Cloud Compute right now.
enum PCCCapability: Sendable, Equatable {
    /// The build's SDK has no PCC types at all (the iOS 26 SDK). Z1 rows
    /// resolve to Z0 as the baseline — not a degradation.
    case sdkUnsupported
    /// PCC exists but can't run now (no network / service unavailable).
    /// A Z1 row falls back to its degraded zone — a real, disclosed degradation.
    case unavailable
    /// PCC is available with quota headroom.
    case available
    /// Quota approaching/reached (or status unrecognized — the conservative
    /// arm, spec 017 R3 / V13). Interactive intents fall back first.
    case quotaConstrained
}

/// Why the router resolved the way it did (logged, never shown raw to users —
/// spec 014 R2 owns user-facing degradation copy).
enum RouteReason: String, Sendable, Equatable {
    case z0Baseline            // the row's default zone is already Z0
    case pinnedToDevice        // user's on-device-only setting (REQ-INT-004)
    case pccSDKUnsupported     // iOS 26 SDK: Z1 resolves to Z0 baseline
    case pccUnavailableFallback // live fallback: PCC advertised but down
    case quotaFallback         // live fallback: quota constrained
    case z1                    // running where the table asked
}

/// One row of the routing table (spec 017 R2 acceptance: value-typed).
struct RoutingRow: Sendable, Equatable {
    let intent: GenerationIntent
    /// Where this intent wants to run. Reasoning level rides on the zone value.
    let defaultZone: TrustZone
    /// Where it falls back to. `nil` = no degradation path exists (the row can
    /// only run at its default zone).
    let degradedZone: TrustZone?
    let priority: QuotaPriority
}

/// The routing decision for one request. `requestedZone` is set BEFORE the
/// generation call (spec 014 R1 rule); `executionZone` is what the artifact
/// persists as `zoneUsed`.
struct ResolvedRoute: Sendable, Equatable {
    let intent: GenerationIntent
    let requestedZone: TrustZone
    let executionZone: TrustZone
    /// REQ-INT-010: degraded output must use the prompt variant tuned for the
    /// smaller model — never the heavy prompt behind the light model.
    let useDegradedPrompt: Bool
    /// True only for a live, disclosed fallback (spec 017 R4) — never for the
    /// iOS 26 Z0 baseline or the user's own Z0 pin.
    let wasDegraded: Bool
    let reason: RouteReason
}

enum ModelRouter {

    /// The routing table (spec 017 R2, source doc §7.2 subset for the intents
    /// this app currently generates). Future rows — kept here as documentation
    /// so extension is a one-row edit with recorded rationale:
    ///   weekly reflection  → .z1AppleContent(.moderate), degrade .z0Device, .scheduled
    ///   monthly insight    → .z1AppleContent(.deep),     degrade .z0Device, .scheduled
    static let table: [RoutingRow] = [
        RoutingRow(
            intent: .ask,
            defaultZone: .z1AppleContent(reasoningLevel: .light),
            degradedZone: .z0Device,
            priority: .interactive
        ),
        RoutingRow(
            intent: .summary,
            defaultZone: .z0Device,
            degradedZone: nil,
            priority: .interactive
        ),
        RoutingRow(
            intent: .profileEstimate,
            defaultZone: .z0Device,
            degradedZone: nil,
            priority: .interactive
        )
    ]

    /// The row for an intent. The table is exhaustive over `GenerationIntent`
    /// (enforced by ModelRouterTests); the fallback row is defensive only.
    static func row(for intent: GenerationIntent) -> RoutingRow {
        table.first { $0.intent == intent }
            ?? RoutingRow(intent: intent, defaultZone: .z0Device, degradedZone: nil, priority: .interactive)
    }

    /// Resolve where a request runs. Pure function of (intent, pin, capability)
    /// so the full matrix is unit-testable with no model.
    static func resolve(
        intent: GenerationIntent,
        pinnedToDevice: Bool,
        pccCapability: PCCCapability
    ) -> ResolvedRoute {
        let row = row(for: intent)

        // Z0 rows never consult the PCC seam at all.
        guard row.defaultZone.carriesContentOffDevice else {
            return ResolvedRoute(
                intent: intent,
                requestedZone: row.defaultZone,
                executionZone: row.defaultZone,
                useDegradedPrompt: false,
                wasDegraded: false,
                reason: .z0Baseline
            )
        }

        // REQ-INT-004: the pin overrides the request itself — the requested
        // zone becomes Z0, so no PCC model can be constructed downstream.
        if pinnedToDevice {
            return ResolvedRoute(
                intent: intent,
                requestedZone: .z0Device,
                executionZone: .z0Device,
                useDegradedPrompt: false,
                wasDegraded: false,
                reason: .pinnedToDevice
            )
        }

        switch pccCapability {
        case .sdkUnsupported:
            // iOS 26 baseline: Z0 with the base prompt, honestly undegrated —
            // there was never a Z1 to degrade from on this build.
            return ResolvedRoute(
                intent: intent,
                requestedZone: row.defaultZone,
                executionZone: .z0Device,
                useDegradedPrompt: false,
                wasDegraded: false,
                reason: .pccSDKUnsupported
            )
        case .available:
            return ResolvedRoute(
                intent: intent,
                requestedZone: row.defaultZone,
                executionZone: row.defaultZone,
                useDegradedPrompt: false,
                wasDegraded: false,
                reason: .z1
            )
        case .unavailable, .quotaConstrained:
            // Live fallback (spec 017 R4): automatic, completes successfully,
            // disclosed — degraded prompt variant, wasDegraded persisted true.
            return ResolvedRoute(
                intent: intent,
                requestedZone: row.defaultZone,
                executionZone: row.degradedZone ?? .z0Device,
                useDegradedPrompt: true,
                wasDegraded: true,
                reason: pccCapability == .unavailable ? .pccUnavailableFallback : .quotaFallback
            )
        }
    }
}
