//
//  QuotaGovernor.swift
//  MeetMemento
//
//  Spec 017 R3 / REQ-INT-005–008. An actor that answers exactly one question:
//  what PCC capability does this intent get right now?
//
//  Pure Swift — the PCC quota surface is mirrored behind `QuotaStatusProviding`
//  rather than imported, so the governor is fully testable without the SDK, a
//  device, or a network (CONSTITUTION §4 rule 5).
//
//  **Reactive-first, deliberately.** Verification item V4 is open: the daily
//  limit may be per-user across apps rather than per-app (`limitIncreaseSuggestion`
//  points at iCloud+, which implies per-user). If it is, Memento can never know
//  the true remaining budget — another app may spend it. So this type observes
//  quota and treats reservation as advisory. There is **no remaining-request
//  arithmetic anywhere**, and `QuotaSnapshot` structurally cannot carry a count:
//  a "3 requests left" UI would be a lie on a per-user limit.
//

import Foundation

/// Mirror of `PrivateCloudComputeLanguageModel.QuotaUsage.Status`.
///
/// The SDK enum is **not** `@frozen` (verified against the iOS 27.0 SDK,
/// 27A5228h), so a case can appear that this build has never seen. `unknown` is
/// that arm, and it is treated as constrained rather than trapping or silently
/// misrouting — spec 017 R3's V13 guard.
enum QuotaStatus: Equatable, Sendable {
    case belowLimit
    case limitReached
    case unknown
}

/// What the app knows about PCC budget at a point in time.
///
/// Note what is absent: any count, remainder, or percentage. That omission is a
/// requirement (REQ-INT-007 / V4), not an oversight — see the file header.
/// `resetDate` is a *date*, not a quantity: technology/02 §6 recommends
/// scheduling a deferred reflection off it instead of polling.
struct QuotaSnapshot: Equatable, Sendable {
    let status: QuotaStatus
    /// From `QuotaUsage.Status.BelowLimit.isApproachingLimit`. Meaningful only
    /// when `status == .belowLimit`.
    let isApproachingLimit: Bool
    let resetDate: Date?

    static let unknown = QuotaSnapshot(status: .unknown, isApproachingLimit: false, resetDate: nil)
}

/// The seam over the SDK's quota surface. Returning `nil` means "this build has
/// no PCC at all" — distinct from "PCC exists and is out of budget".
protocol QuotaStatusProviding: Sendable {
    func snapshot() async -> QuotaSnapshot?
}

/// The only provider that exists on the iOS 26 SDK: there is no
/// `PrivateCloudComputeLanguageModel` to read, so there is no quota to report.
/// Makes the governor inert in production today while keeping it fully
/// exercisable in tests through stub providers.
struct NoPCCQuotaProvider: QuotaStatusProviding {
    func snapshot() async -> QuotaSnapshot? { nil }
}

actor QuotaGovernor {
    static let shared = QuotaGovernor()

    private let provider: QuotaStatusProviding

    init(provider: QuotaStatusProviding = NoPCCQuotaProvider()) {
        self.provider = provider
    }

    /// The capability this intent gets right now.
    ///
    /// Priority is fixed and not configurable (spec 017 R3): when budget is
    /// tight, interactive chat yields before scheduled synthesis. On
    /// `isApproachingLimit` chat degrades to Z0 *first*, preserving what is left
    /// for a reflection the user did not ask for in the moment and cannot retry.
    func capability(for priority: QuotaPriority) async -> PCCCapability {
        guard let snapshot = await provider.snapshot() else { return .sdkUnsupported }

        switch snapshot.status {
        case .limitReached:
            return .quotaConstrained

        case .unknown:
            // V13 guard: an unenumerated status degrades gracefully rather than
            // trapping. Conservative — assume constrained.
            return .quotaConstrained

        case .belowLimit:
            guard snapshot.isApproachingLimit else { return .available }
            // Approaching: scheduled work keeps its slot, interactive yields.
            return priority >= .scheduled ? .available : .quotaConstrained
        }
    }

    /// The date the limit resets, when the platform reports one. Exposed so a
    /// deferred scheduled reflection can be re-armed off it rather than polled
    /// (technology/02 §6). Never a remaining-budget signal.
    func resetDate() async -> Date? {
        await provider.snapshot()?.resetDate
    }
}
