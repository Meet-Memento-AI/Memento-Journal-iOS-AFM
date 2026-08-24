import XCTest
@testable import MeetMemento

/// Spec 017 R8 / REQ-PRM-001: "given any intent/zone/degraded combination the
/// router can produce, when the registry resolves it, then a bundled prompt with
/// a version identifier is returned — a missing combination is a test failure,
/// not a runtime fallback to a 'closest' prompt."
final class PromptRegistryResolutionTests: XCTestCase {

    /// Every zone the routing table can put on a request, plus the content-free
    /// zone for completeness.
    private var allZones: [TrustZone] {
        [.z0Device, .z1AppleContentFree] + PCCReasoningLevel.allCases.map { .z1AppleContent(reasoningLevel: $0) }
    }

    func test_everyRouterProducibleCombination_resolves() {
        for intent in GenerationIntent.allCases {
            for zone in allZones {
                for degraded in [false, true] {
                    let resolved = PromptRegistry.resolve(intent: intent, zone: zone, degraded: degraded)

                    XCTAssertFalse(resolved.text.isEmpty,
                                   "\(intent)/\(zone)/degraded=\(degraded) resolved to an empty prompt")
                    XCTAssertFalse(resolved.version.isEmpty,
                                   "\(intent)/\(zone)/degraded=\(degraded) resolved without a version")
                    XCTAssertTrue(resolved.version.contains("@"),
                                  "version '\(resolved.version)' is not addressable — spec 022 pins prompts by version")
                }
            }
        }
    }

    /// The combinations the router can *actually* emit, derived from the table
    /// rather than enumerated by hand — so a routing change that produces a new
    /// combination is covered automatically instead of silently escaping.
    func test_everyCombinationTheRouterEmits_resolves() {
        let capabilities: [PCCCapability] = [.available, .sdkUnsupported, .unavailable, .quotaConstrained]

        for intent in GenerationIntent.allCases {
            for capability in capabilities {
                for pinned in [true, false] {
                    let route = ModelRouter.resolve(intent: intent, pinnedToDevice: pinned, pccCapability: capability)
                    let resolved = PromptRegistry.resolve(intent: intent,
                                                          zone: route.executionZone,
                                                          degraded: route.useDegradedPrompt)

                    XCTAssertFalse(resolved.text.isEmpty)
                    XCTAssertFalse(resolved.version.isEmpty)
                }
            }
        }
    }

    /// REQ-INT-010's proof mechanism. A degraded artifact's persisted
    /// promptVersion must name the degraded variant, not the full one — that is
    /// how a test (and later the quality study) can tell which prompt actually
    /// ran. If these versions ever collide, the disclosure becomes unfalsifiable.
    func test_degradedAsk_resolvesToADistinctPromptAndVersion() {
        let full = PromptRegistry.resolve(intent: .ask, zone: .z0Device, degraded: false)
        let degraded = PromptRegistry.resolve(intent: .ask, zone: .z0Device, degraded: true)

        XCTAssertNotEqual(full.version, degraded.version,
                          "the degraded variant must be identifiable by version")
        XCTAssertNotEqual(full.text, degraded.text,
                          "degraded output must use a prompt tuned for the smaller model, "
                          + "never the heavy prompt behind a lighter model (REQ-INT-010)")
    }

    /// `resolve` is a keying layer over the existing registry, not a second
    /// source of prompt text. If these diverge, the contract tests that pin
    /// `instructions(for:)` would stop describing what actually runs.
    func test_resolve_agreesWithTheUnderlyingRegistry() {
        for intent in GenerationIntent.allCases {
            for degraded in [false, true] {
                let viaResolve = PromptRegistry.resolve(intent: intent, zone: .z0Device, degraded: degraded)
                let viaInstructions = PromptRegistry.instructions(for: intent, degraded: degraded)

                XCTAssertEqual(viaResolve.text, viaInstructions.text)
                XCTAssertEqual(viaResolve.version, viaInstructions.version)
            }
        }
    }

    /// Personalization must survive the new keying layer — it is part of what
    /// the version string claims (the `+p4` suffix), so dropping it here would
    /// mislabel every personalized artifact.
    func test_resolve_carriesPersonalizationThrough() {
        let personalization = PromptPersonalization(
            firstName: "Ada",
            reflection: "I want to notice when I am overcommitting.",
            goals: [],
            promptLens: nil
        )

        let plain = PromptRegistry.resolve(intent: .ask, zone: .z0Device, degraded: false)
        let personalized = PromptRegistry.resolve(intent: .ask, zone: .z0Device, degraded: false,
                                                  personalization: personalization)

        XCTAssertNotEqual(plain.version, personalized.version)
        XCTAssertTrue(personalized.text.count > plain.text.count)
    }

    func test_everyAskChannel_resolves() {
        for channel in ReplyChannel.allCases {
            for degraded in [false, true] {
                let resolved = PromptRegistry.resolve(
                    intent: .ask, zone: .z0Device, degraded: degraded, channel: channel
                )
                XCTAssertFalse(resolved.text.isEmpty, "\(channel) degraded=\(degraded)")
                XCTAssertTrue(resolved.version.contains("@"), "\(channel) \(resolved.version)")
            }
        }
    }

    func test_phaticChannel_resolvesToChatLight() {
        let full = PromptRegistry.resolve(intent: .ask, zone: .z0Device, degraded: false, channel: .phatic)
        let degraded = PromptRegistry.resolve(intent: .ask, zone: .z0Device, degraded: true, channel: .phatic)
        XCTAssertEqual(full.version, "chat-light@4")
        XCTAssertEqual(degraded.version, "chat-light-degraded@4")
        XCTAssertNotEqual(full.version, degraded.version)
        XCTAssertFalse(full.text.contains("How a reply is built"))
    }

    /// Named for the version at the time; the contract is the *channel*, not the
    /// number — `.companion` runs the heavy prompt, not `chat-light`.
    func test_companionChannel_staysOnTheHeavyPrompt() {
        let resolved = PromptRegistry.resolve(intent: .ask, zone: .z0Device, degraded: false, channel: .companion)
        XCTAssertEqual(resolved.version, "ask@15")
    }

    func test_phatic_agreesWithInstructions() {
        let viaResolve = PromptRegistry.resolve(intent: .ask, zone: .z0Device, degraded: false, channel: .phatic)
        let viaInstructions = PromptRegistry.instructions(for: .ask, channel: .phatic)
        XCTAssertEqual(viaResolve.text, viaInstructions.text)
        XCTAssertEqual(viaResolve.version, viaInstructions.version)
    }
}
