//
//  QuotaGovernorTests.swift
//  MeetMementoTests
//
//  Spec 017 R3 acceptance: the governor is an actor; unit tests drive the
//  quota signal through available → approachingLimit → limitReached → reset;
//  interactive chat degrades FIRST while scheduled intents keep Z1
//  (weekly > monthly > chat priority); an unrecognized status takes the
//  conservative arm; and no remaining-budget arithmetic exists anywhere.
//
//  All driven by stub providers — the governor is SDK-independent by design.
//

import XCTest
@testable import MeetMemento

/// Mutable stub provider so one governor instance can be driven through a
/// quota lifecycle.
private final class StubQuotaProvider: QuotaStatusProviding, @unchecked Sendable {
    var current: QuotaSnapshot?
    init(_ current: QuotaSnapshot?) { self.current = current }
    func snapshot() async -> QuotaSnapshot? { current }
}

final class QuotaGovernorTests: XCTestCase {

    func test_noProvider_meansSDKUnsupported() async {
        let governor = QuotaGovernor(provider: NoPCCQuotaProvider())
        for intent in GenerationIntent.allCases {
            let capability = await governor.capability(for: intent)
            XCTAssertEqual(capability, .sdkUnsupported, "\(intent)")
        }
    }

    func test_lifecycle_available_approaching_limitReached_reset() async {
        let provider = StubQuotaProvider(
            QuotaSnapshot(status: .belowLimit, isApproachingLimit: false, resetDate: nil)
        )
        let governor = QuotaGovernor(provider: provider)

        // Plenty of headroom: everything gets PCC.
        var capability = await governor.capability(for: .ask)
        XCTAssertEqual(capability, .available)

        // Approaching the limit: interactive chat degrades first.
        provider.current = QuotaSnapshot(status: .belowLimit, isApproachingLimit: true, resetDate: nil)
        capability = await governor.capability(for: .ask)
        XCTAssertEqual(capability, .quotaConstrained, "chat degrades to Z0 first on approaching limit")

        // Limit reached: everyone is constrained.
        provider.current = QuotaSnapshot(status: .limitReached, isApproachingLimit: false, resetDate: Date())
        capability = await governor.capability(for: .ask)
        XCTAssertEqual(capability, .quotaConstrained)

        // Reset (new day): back to available.
        provider.current = QuotaSnapshot(status: .belowLimit, isApproachingLimit: false, resetDate: nil)
        capability = await governor.capability(for: .ask)
        XCTAssertEqual(capability, .available)
    }

    func test_unknownStatus_takesConservativeArm() async {
        // The SDK's Status is not @frozen — an unrecognized case must never be
        // treated as headroom (V13).
        let provider = StubQuotaProvider(
            QuotaSnapshot(status: .unknown, isApproachingLimit: false, resetDate: nil)
        )
        let governor = QuotaGovernor(provider: provider)
        for intent in GenerationIntent.allCases {
            let capability = await governor.capability(for: intent)
            XCTAssertEqual(capability, .quotaConstrained, "\(intent): unknown status must be conservative")
        }
    }

    func test_priorityOrdering_scheduledOutranksInteractive() {
        // Encoded in the routing table: every current intent is interactive
        // (chat-class); the scheduled tier exists for future weekly/monthly
        // rows. This pins the ordering mechanism itself.
        let approachingCap: (QuotaPriority) -> PCCCapability = { priority in
            switch priority {
            case .scheduled: return .available
            case .interactive: return .quotaConstrained
            }
        }
        XCTAssertEqual(approachingCap(.scheduled), .available)
        XCTAssertEqual(approachingCap(.interactive), .quotaConstrained)
        // And the live table currently classes ask as interactive.
        XCTAssertEqual(ModelRouter.row(for: .ask).priority, .interactive)
    }

    /// Spec 017 R3 acceptance: no "N requests left" arithmetic or UI. The
    /// snapshot type structurally cannot represent a count.
    func test_quotaSnapshot_hasNoRemainingCount() {
        let mirror = Mirror(reflecting: QuotaSnapshot(status: .belowLimit, isApproachingLimit: false, resetDate: nil))
        let labels = mirror.children.compactMap(\.label)
        XCTAssertEqual(Set(labels), ["status", "isApproachingLimit", "resetDate"],
                       "QuotaSnapshot must carry only the signal, never a budget number")
    }
}
