//
//  ModelRouterTests.swift
//  MeetMementoTests
//
//  Spec 017 R2 acceptance: the routing table is a value-typed data structure,
//  exhaustive over GenerationIntent (this suite breaks when an intent is
//  added without a row); the user's Z0-pin resolves EVERY intent to
//  `.z0Device` (REQ-INT-004); and degradation honesty holds — the iOS 26
//  baseline is not "degraded", while live PCC fallbacks are, with the
//  degraded prompt variant selected (REQ-INT-010).
//

import XCTest
@testable import MeetMemento

final class ModelRouterTests: XCTestCase {

    // MARK: Table shape

    func test_table_isExhaustiveOverGenerationIntent() {
        for intent in GenerationIntent.allCases {
            XCTAssertTrue(
                ModelRouter.table.contains { $0.intent == intent },
                "Routing table is missing a row for \(intent) — add one (spec 017 R2)"
            )
        }
        XCTAssertEqual(
            ModelRouter.table.count, GenerationIntent.allCases.count,
            "One row per intent — duplicates or orphan rows are a table bug"
        )
    }

    func test_table_expectedRows() {
        XCTAssertEqual(ModelRouter.row(for: .ask).defaultZone, .z1AppleContent(reasoningLevel: .light))
        XCTAssertEqual(ModelRouter.row(for: .ask).degradedZone, .z0Device)
        XCTAssertEqual(ModelRouter.row(for: .ask).priority, .interactive)
        XCTAssertEqual(ModelRouter.row(for: .summary).defaultZone, .z0Device)
        XCTAssertEqual(ModelRouter.row(for: .profileEstimate).defaultZone, .z0Device)
    }

    // MARK: Z0-pin (REQ-INT-004)

    func test_z0Pin_resolvesEveryIntentToDevice_regardlessOfPCC() {
        for intent in GenerationIntent.allCases {
            for capability in [PCCCapability.sdkUnsupported, .unavailable, .available, .quotaConstrained] {
                let route = ModelRouter.resolve(intent: intent, pinnedToDevice: true, pccCapability: capability)
                XCTAssertEqual(route.executionZone, .z0Device, "\(intent)/\(capability)")
                XCTAssertFalse(route.wasDegraded, "the pin is a user choice, not a degradation")
                XCTAssertFalse(route.useDegradedPrompt)
                if ModelRouter.row(for: intent).defaultZone.carriesContentOffDevice {
                    XCTAssertEqual(route.requestedZone, .z0Device, "the pin overrides the request itself")
                    XCTAssertEqual(route.reason, .pinnedToDevice)
                }
            }
        }
    }

    // MARK: Honesty matrix

    func test_z0Rows_neverConsultPCC() {
        for capability in [PCCCapability.sdkUnsupported, .unavailable, .available, .quotaConstrained] {
            let route = ModelRouter.resolve(intent: .summary, pinnedToDevice: false, pccCapability: capability)
            XCTAssertEqual(route.reason, .z0Baseline)
            XCTAssertEqual(route.executionZone, .z0Device)
            XCTAssertFalse(route.wasDegraded)
        }
    }

    func test_iOS26Baseline_isNotDegraded() {
        // sdkUnsupported (the entire iOS 26 SDK): Z1 rows resolve to Z0 as the
        // baseline — base prompt, wasDegraded false. There was never a Z1 to
        // degrade from on this build.
        let route = ModelRouter.resolve(intent: .ask, pinnedToDevice: false, pccCapability: .sdkUnsupported)
        XCTAssertEqual(route.requestedZone, .z1AppleContent(reasoningLevel: .light))
        XCTAssertEqual(route.executionZone, .z0Device)
        XCTAssertFalse(route.wasDegraded)
        XCTAssertFalse(route.useDegradedPrompt)
        XCTAssertEqual(route.reason, .pccSDKUnsupported)
    }

    func test_pccAvailable_runsAtRequestedZone() {
        let route = ModelRouter.resolve(intent: .ask, pinnedToDevice: false, pccCapability: .available)
        XCTAssertEqual(route.executionZone, .z1AppleContent(reasoningLevel: .light))
        XCTAssertFalse(route.wasDegraded)
        XCTAssertEqual(route.reason, .z1)
    }

    func test_liveFallbacks_areDisclosedDegradations_withDegradedPrompt() {
        for (capability, reason) in [(PCCCapability.unavailable, RouteReason.pccUnavailableFallback),
                                     (.quotaConstrained, .quotaFallback)] {
            let route = ModelRouter.resolve(intent: .ask, pinnedToDevice: false, pccCapability: capability)
            XCTAssertEqual(route.requestedZone, .z1AppleContent(reasoningLevel: .light),
                           "zone set before the call must reflect the table's intent")
            XCTAssertEqual(route.executionZone, .z0Device)
            XCTAssertTrue(route.wasDegraded, "a live fallback is a disclosed degradation (017 R4)")
            XCTAssertTrue(route.useDegradedPrompt, "REQ-INT-010: degraded output uses the degraded prompt variant")
            XCTAssertEqual(route.reason, reason)
        }
    }
}
