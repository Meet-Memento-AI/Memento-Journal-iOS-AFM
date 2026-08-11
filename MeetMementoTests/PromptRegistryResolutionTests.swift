//
//  PromptRegistryResolutionTests.swift
//  MeetMementoTests
//
//  REQ-PRM-001 acceptance: registry resolution is exhaustive over every
//  router-producible `(intent, zone, degraded)` combination — a missing
//  combination is a test failure here, never a runtime fallback to a
//  "closest" prompt. Also pins REQ-INT-010's proof mechanism: a degraded
//  route resolves to a prompt whose VERSION names the degraded variant, so
//  persisted artifacts are attributable (REQ-PRM-004).
//

import XCTest
@testable import MeetMemento

final class PromptRegistryResolutionTests: XCTestCase {

    /// Every route the router can actually emit, across the full input space.
    private func allProducibleRoutes() -> [ResolvedRoute] {
        var routes: [ResolvedRoute] = []
        for intent in GenerationIntent.allCases {
            for pinned in [false, true] {
                for capability in [PCCCapability.sdkUnsupported, .unavailable, .available, .quotaConstrained] {
                    routes.append(ModelRouter.resolve(intent: intent, pinnedToDevice: pinned, pccCapability: capability))
                }
            }
        }
        return routes
    }

    func test_everyProducibleRoute_resolvesToAPrompt() {
        for route in allProducibleRoutes() {
            let resolved = PromptRegistry.resolve(
                intent: route.intent,
                zone: route.executionZone,
                degraded: route.useDegradedPrompt
            )
            XCTAssertFalse(resolved.text.isEmpty,
                           "no prompt for (\(route.intent), \(route.executionZone), degraded: \(route.useDegradedPrompt))")
            XCTAssertFalse(resolved.version.isEmpty)
        }
    }

    func test_degradedRoutes_resolveToDegradedVersions() {
        // REQ-INT-010: the persisted promptVersion is the proof the degraded
        // variant actually ran.
        let degradedAsk = PromptRegistry.resolve(intent: .ask, zone: .z0Device, degraded: true)
        let baseAsk = PromptRegistry.resolve(intent: .ask, zone: .z0Device, degraded: false)
        XCTAssertNotEqual(degradedAsk.version, baseAsk.version)
        XCTAssertTrue(degradedAsk.version.contains("degraded"), degradedAsk.version)
        XCTAssertLessThan(degradedAsk.text.count, baseAsk.text.count,
                          "the degraded variant is the shorter prompt tuned for the smaller model")
    }

    func test_personalization_taggedInVersion() {
        let personalization = PromptPersonalization(
            firstName: "Alex",
            reflection: nil,
            goals: ["Stress & Overwhelm"],
            promptLens: "Lean toward noticing stress patterns."
        )
        let resolved = PromptRegistry.resolve(intent: .ask, zone: .z0Device, degraded: false, personalization: personalization)
        XCTAssertTrue(resolved.version.hasSuffix("+p2"),
                      "personalized prompts must be attributable as such (REQ-PRM-004): \(resolved.version)")
    }

    func test_zoneDoesNotForkPromptText_yet() {
        // Documented current behavior: Z0/Z1 share prompt text until the
        // PCC-tuned variants are authored (iOS 27 SDK pass). This test exists
        // so that change is deliberate, not accidental.
        for intent in GenerationIntent.allCases {
            let z0 = PromptRegistry.resolve(intent: intent, zone: .z0Device, degraded: false)
            let z1 = PromptRegistry.resolve(intent: intent, zone: .z1AppleContent(reasoningLevel: .light), degraded: false)
            XCTAssertEqual(z0.text, z1.text)
            XCTAssertEqual(z0.version, z1.version)
        }
    }
}
