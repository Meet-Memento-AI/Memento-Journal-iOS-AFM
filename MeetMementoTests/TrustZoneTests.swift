import XCTest
@testable import MeetMemento

/// Spec 014 R1's acceptance criteria for the trust-boundary contract.
///
/// The `Codable` round-trip is not ceremony: spec 015 persists the zone on
/// `Reflection`/`Turn`, and spec 022's quality study joins on it. A zone that
/// survives a write/read cycle as a *different* zone would silently mislabel
/// where a generation ran, which is the one thing this type exists to prevent.
final class TrustZoneTests: XCTestCase {
    private func roundTrip(_ zone: TrustZone) throws -> TrustZone {
        let data = try JSONEncoder().encode(zone)
        return try JSONDecoder().decode(TrustZone.self, from: data)
    }

    func test_trustZone_codableRoundTrip_perCase() throws {
        // One instance of each case — including every reasoning level, since the
        // level rides on the zone value (spec 017 R1) and is therefore part of
        // what has to survive persistence.
        let cases: [TrustZone] = [
            .z0Device,
            .z1AppleContentFree,
            .z1AppleContent(reasoningLevel: .light),
            .z1AppleContent(reasoningLevel: .moderate),
            .z1AppleContent(reasoningLevel: .deep),
        ]

        for zone in cases {
            XCTAssertEqual(try roundTrip(zone), zone, "\(zone) did not survive a Codable round-trip")
        }
    }

    func test_trustZone_reasoningLevelIsNotCollapsed() throws {
        // A round-trip that lost the level would still decode as
        // `.z1AppleContent` and pass a weaker test. Assert the levels stay
        // distinct from each other.
        let light = try roundTrip(.z1AppleContent(reasoningLevel: .light))
        let deep = try roundTrip(.z1AppleContent(reasoningLevel: .deep))
        XCTAssertNotEqual(light, deep)
    }

    /// REQ-PRIV-001 is about *content*, not about whether a network call
    /// happened. `.z1AppleContentFree` is a real network call carrying no
    /// journal text; collapsing it into either neighbour misrepresents it.
    func test_carriesContentOffDevice_isAboutContentNotNetwork() {
        XCTAssertFalse(TrustZone.z0Device.carriesContentOffDevice)
        XCTAssertFalse(TrustZone.z1AppleContentFree.carriesContentOffDevice)
        for level in PCCReasoningLevel.allCases {
            XCTAssertTrue(TrustZone.z1AppleContent(reasoningLevel: level).carriesContentOffDevice)
        }
    }

    /// Provenance identifiers are a wire format (REQ-PRM-004) — spec 022's
    /// harness joins on them, so a rename is a breaking change, not a tidy-up.
    func test_identifier_isStableAndDistinct() {
        XCTAssertEqual(TrustZone.z0Device.identifier, "z0.device")
        XCTAssertEqual(TrustZone.z1AppleContentFree.identifier, "z1.apple.content-free")
        XCTAssertEqual(TrustZone.z1AppleContent(reasoningLevel: .light).identifier, "z1.apple.content.light")

        let all: [TrustZone] = [.z0Device, .z1AppleContentFree]
            + PCCReasoningLevel.allCases.map { .z1AppleContent(reasoningLevel: $0) }
        XCTAssertEqual(Set(all.map(\.identifier)).count, all.count, "identifiers must be distinct")
    }

    /// `PCCReasoningLevel` is deliberately three cases. The SDK's
    /// `ContextOptions.ReasoningLevel` also has `.custom(String)`, but
    /// `technology/02` §5 is explicit that the routing table has no use for it
    /// and it must not appear in the router's column type.
    func test_reasoningLevel_hasExactlyTheThreeRoutableCases() {
        XCTAssertEqual(PCCReasoningLevel.allCases.map(\.rawValue), ["light", "moderate", "deep"])
    }
}
