//
//  QuotaGovernor.swift
//  MeetMemento
//
//  Reactive-first PCC quota governance (spec 017 R3 / REQ-INT-005…008).
//  Priority is fixed: scheduled synthesis (future weekly > monthly) outranks
//  interactive chat — on `isApproachingLimit`, chat degrades to Z0 FIRST while
//  scheduled intents keep their Z1 slot.
//
//  Deliberately NO remaining-budget arithmetic and no "N requests left"
//  surface anywhere (spec 017 R3 acceptance / V4 posture): the SDK exposes a
//  per-user budget signal, not a number, and any reservation math would be
//  advisory fiction. The governor reads the signal reactively and answers one
//  question: what PCC capability does this intent get right now?
//
//  iOS 26 SDK: `PrivateCloudComputeLanguageModel` does not exist, so the sole
//  provider is `NoPCCQuotaProvider` (nil snapshot → `.sdkUnsupported`) — the
//  governor is inert in production but its full lifecycle is unit-tested via
//  stub providers (QuotaGovernorTests). The iOS 27 pass adds the FM-backed
//  provider inside the single-importer file; `QuotaSnapshot.resetDate` is
//  carried so that pass can SCHEDULE retry of a deferred scheduled reflection
//  off the reset date instead of polling (technology/02 §6).
//
//  No `import FoundationModels` — pure Swift.
//

import Foundation

/// Mirror of the PCC quota signal, SDK-independent so the governor and its
/// tests compile on any SDK. `unknown` is the mandatory conservative arm:
/// the SDK's `Status` is NOT `@frozen` (technology/02 §6), so an unrecognized
/// case must never be treated as headroom (spec 017 R3 / V13).
enum QuotaStatus: Sendable, Equatable {
    case belowLimit
    case limitReached
    case unknown
}

struct QuotaSnapshot: Sendable, Equatable {
    let status: QuotaStatus
    /// Meaningful only when `status == .belowLimit`.
    let isApproachingLimit: Bool
    /// When the per-user budget resets, if the SDK reports it.
    let resetDate: Date?
}

/// The seam the iOS 27 FM-backed provider will fill. Returning `nil` means
/// this build has no PCC at all (the iOS 26 SDK).
protocol QuotaStatusProviding: Sendable {
    func snapshot() async -> QuotaSnapshot?
}

/// The only provider that exists on the iOS 26 SDK.
struct NoPCCQuotaProvider: QuotaStatusProviding {
    func snapshot() async -> QuotaSnapshot? { nil }
}

/// Answers "what PCC capability does this intent get right now?" for the
/// router. An actor (spec 017 R3 acceptance) so the iOS 27 provider can add
/// observation/caching without changing call sites.
actor QuotaGovernor {
    static let shared = QuotaGovernor(provider: NoPCCQuotaProvider())

    private let provider: QuotaStatusProviding

    init(provider: QuotaStatusProviding) {
        self.provider = provider
    }

    /// Capability for one intent, applying the priority order to the shared
    /// budget signal. Pure mapping — all state lives in the provider.
    func capability(for intent: GenerationIntent) async -> PCCCapability {
        guard let snapshot = await provider.snapshot() else {
            return .sdkUnsupported
        }
        switch snapshot.status {
        case .limitReached:
            return .quotaConstrained
        case .unknown:
            // Conservative arm: never spend what might not exist.
            return .quotaConstrained
        case .belowLimit:
            guard snapshot.isApproachingLimit else { return .available }
            // Approaching the limit: interactive intents (chat) degrade first
            // so scheduled synthesis keeps its slot (weekly > monthly > chat).
            switch ModelRouter.row(for: intent).priority {
            case .scheduled:
                return .available
            case .interactive:
                return .quotaConstrained
            }
        }
    }
}
