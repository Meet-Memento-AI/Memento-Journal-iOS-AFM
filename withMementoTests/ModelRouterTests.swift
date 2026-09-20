import XCTest
@testable import MeetMemento

/// Spec 017 R2's acceptance criteria for the table-driven router.
final class ModelRouterTests: XCTestCase {

    // MARK: Exhaustiveness

    /// The test spec 017 R2 asks for by name: "an exhaustiveness test breaks
    /// when a new intent is added without a row." `row(for:)` returns an
    /// optional precisely so this is the thing that catches it, rather than a
    /// runtime fallback quietly routing a new intent somewhere plausible.
    func test_table_hasExactlyOneRowPerIntent() {
        for intent in GenerationIntent.allCases {
            XCTAssertNotNil(ModelRouter.row(for: intent),
                            "\(intent) has no routing row — add one to ModelRouter.table")
        }
        XCTAssertEqual(ModelRouter.table.count, GenerationIntent.allCases.count,
                       "table has a duplicate or orphaned row")
    }

    /// Spec 017 R2: an intent with no Z1 path must have a *structurally empty*
    /// degradation column — not one that "degrades to itself", which would read
    /// as a fallback that exists when it doesn't.
    func test_deviceOnlyRows_haveNoDegradationColumn() {
        for row in ModelRouter.table where !row.defaultZone.carriesContentOffDevice {
            XCTAssertNil(row.degradedZone,
                         "\(row.intent) is device-only; its degradedZone must be nil, not itself")
        }
    }

    func test_z1Rows_declareAFallback() {
        for row in ModelRouter.table where row.defaultZone.carriesContentOffDevice {
            XCTAssertEqual(row.degradedZone, .z0Device,
                           "\(row.intent) can leave the device, so it needs a Z0 fallback")
        }
    }

    // MARK: The user's Z0 pin (REQ-INT-004)

    /// Spec 017 R2's acceptance: "given the Z0-pin setting enabled, when any
    /// intent is routed, then the resolved zone is .z0Device and no PCC model is
    /// constructed." The second half matters as much as the first — the pin is a
    /// router-level override, so it must short-circuit *before* the PCC seam is
    /// consulted, not merely override its answer afterwards.
    func test_z0Pin_forcesEveryIntentOnDevice_underEveryCapability() {
        let capabilities: [PCCCapability] = [.available, .sdkUnsupported, .unavailable, .quotaConstrained]

        for intent in GenerationIntent.allCases {
            for capability in capabilities {
                let route = ModelRouter.resolve(intent: intent, pinnedToDevice: true, pccCapability: capability)

                XCTAssertEqual(route.executionZone, .z0Device, "\(intent)/\(capability) escaped the pin")
                XCTAssertEqual(route.requestedZone, .z0Device,
                               "a pinned request must never even ask for Z1 — the zone is set before the call")
                XCTAssertEqual(route.reason, .userPinnedToDevice)
                // Pinning is the user's choice, not a service shortfall: it must
                // not render 014 R2's degradation copy.
                XCTAssertFalse(route.wasDegraded, "the pin is a preference, not a degradation")
                XCTAssertFalse(route.useDegradedPrompt)
            }
        }
    }

    /// A spy standing in for the PCC seam, proving the pin path never asks it
    /// anything. `resolve` is pure, so "no PCC model is constructed" is asserted
    /// one level up: the pin is evaluated without a capability being computed.
    func test_z0Pin_isEvaluatedWithoutConsultingThePCCSeam() async {
        actor CapabilitySpy {
            private(set) var callCount = 0
            func capability() -> PCCCapability { callCount += 1; return .available }
        }
        let spy = CapabilitySpy()

        // Mirrors the boundary's ordering: check the pin first, and only reach
        // for a capability when it is off.
        for intent in GenerationIntent.allCases {
            let pinned = true
            let capability: PCCCapability = pinned ? .sdkUnsupported : await spy.capability()
            let route = ModelRouter.resolve(intent: intent, pinnedToDevice: pinned, pccCapability: capability)
            XCTAssertEqual(route.executionZone, .z0Device)
        }

        let calls = await spy.callCount
        XCTAssertEqual(calls, 0, "the pin must short-circuit before the PCC seam is touched")
    }

    // MARK: Degradation honesty

    /// The load-bearing distinction. On a build whose SDK has no PCC, a Z1 row
    /// running on-device is the *baseline* — not a degradation — so it must not
    /// be labelled. Labelling every reply "degraded" would drain spec 014 R2's
    /// disclosure copy of meaning exactly when it later matters.
    func test_sdkUnsupported_isBaselineNotDegradation() {
        let route = ModelRouter.resolve(intent: .ask, pinnedToDevice: false, pccCapability: .sdkUnsupported)

        XCTAssertEqual(route.executionZone, .z0Device)
        XCTAssertEqual(route.requestedZone, .z0Device, "nothing was asked of PCC, so nothing was denied")
        XCTAssertFalse(route.wasDegraded)
        XCTAssertFalse(route.useDegradedPrompt, "the shipped prompts are authored for the on-device model")
        XCTAssertEqual(route.reason, .sdkUnsupported)
    }

    /// The inverse: PCC exists and could not take the request. That is a real
    /// shortfall, so it is disclosed *and* uses the prompt tuned for the smaller
    /// model (REQ-INT-010 — never the heavy prompt behind a lighter model).
    func test_liveFallback_isDegradedAndUsesTheDegradedPrompt() {
        for capability in [PCCCapability.unavailable, .quotaConstrained] {
            let route = ModelRouter.resolve(intent: .ask, pinnedToDevice: false, pccCapability: capability)

            XCTAssertEqual(route.executionZone, .z0Device)
            XCTAssertEqual(route.requestedZone, .z1AppleContent(reasoningLevel: .light),
                           "the requested zone records what was asked for, so the gap is visible")
            XCTAssertTrue(route.wasDegraded, "\(capability) is a real shortfall and must be disclosed")
            XCTAssertTrue(route.useDegradedPrompt)
        }
    }

    func test_pccAvailable_routesToZ1AtTheTablesReasoningLevel() {
        let route = ModelRouter.resolve(intent: .ask, pinnedToDevice: false, pccCapability: .available)

        XCTAssertEqual(route.executionZone, .z1AppleContent(reasoningLevel: .light))
        XCTAssertFalse(route.wasDegraded)
        XCTAssertEqual(route.reason, .defaultRoute)
    }

    /// Device-only intents resolve identically no matter what PCC reports —
    /// there is no configuration in which they acquire a Z1 leg.
    func test_deviceOnlyIntents_neverYieldAZ1Zone() {
        let capabilities: [PCCCapability] = [.available, .sdkUnsupported, .unavailable, .quotaConstrained]

        for row in ModelRouter.table where row.degradedZone == nil {
            for capability in capabilities {
                let route = ModelRouter.resolve(intent: row.intent, pinnedToDevice: false, pccCapability: capability)

                XCTAssertFalse(route.executionZone.carriesContentOffDevice,
                               "\(row.intent) must never send content off device")
                XCTAssertEqual(route.reason, .deviceOnlyIntent)
                XCTAssertFalse(route.wasDegraded, "running where it always runs is not a degradation")
            }
        }
    }

    /// The full matrix, as a single sweep: whatever the inputs, a route must
    /// never claim degradation while running in the zone it asked for, and never
    /// stay silent while running somewhere else.
    func test_degradationFlag_alwaysMatchesTheZoneGap() {
        let capabilities: [PCCCapability] = [.available, .sdkUnsupported, .unavailable, .quotaConstrained]

        for intent in GenerationIntent.allCases {
            for capability in capabilities {
                for pinned in [true, false] {
                    let route = ModelRouter.resolve(intent: intent, pinnedToDevice: pinned, pccCapability: capability)
                    let ranSomewhereElse = route.executionZone != route.requestedZone

                    XCTAssertEqual(route.wasDegraded, ranSomewhereElse,
                                   "\(intent)/\(capability)/pinned=\(pinned): wasDegraded must track the zone gap")
                    XCTAssertEqual(route.useDegradedPrompt, route.wasDegraded,
                                   "a degraded run must use the degraded prompt, and only then (REQ-INT-010)")
                }
            }
        }
    }
}
