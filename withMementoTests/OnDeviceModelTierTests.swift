import XCTest
@testable import withMemento

/// Spec 051 R1. The resolver's rules, their order, and the cache's
/// positive-only contract.
final class OnDeviceModelTierTests: XCTestCase {

    private let twelveGBDevice: UInt64 = 11_800_000_000
    private let eightGBDevice: UInt64 = 7_700_000_000

    private func resolve(
        reported: OnDeviceModelTier? = nil,
        available: Bool = true,
        os: Int = 27,
        memory: UInt64
    ) -> ResolvedOnDeviceModelTier {
        OnDeviceModelTierResolver.resolve(
            reported: reported,
            modelAvailable: available,
            osMajorVersion: os,
            physicalMemoryBytes: memory
        )
    }

    // MARK: Rules

    func test_resolver_unavailableModel_isUnknown() {
        XCTAssertEqual(resolve(available: false, memory: twelveGBDevice), .unresolved)
        XCTAssertEqual(resolve(reported: .afm3CoreAdvanced, available: false, memory: twelveGBDevice).tier, .unknown)
    }

    func test_resolver_reportedTier_beatsInference() {
        let result = resolve(reported: .afm3Core, memory: twelveGBDevice)
        XCTAssertEqual(result, ResolvedOnDeviceModelTier(tier: .afm3Core, source: .reported))
    }

    func test_resolver_reportedUnknown_fallsThroughToInference() {
        let result = resolve(reported: .unknown, memory: twelveGBDevice)
        XCTAssertEqual(result, ResolvedOnDeviceModelTier(tier: .afm3CoreAdvanced, source: .inferred))
    }

    func test_resolver_preIOS27_isPreAFM3_regardlessOfMemory() {
        XCTAssertEqual(resolve(os: 26, memory: twelveGBDevice),
                       ResolvedOnDeviceModelTier(tier: .preAFM3, source: .inferred))
        XCTAssertEqual(resolve(os: 26, memory: eightGBDevice).tier, .preAFM3)
    }

    func test_resolver_twelveGBDevice_isCoreAdvanced() {
        XCTAssertEqual(resolve(memory: twelveGBDevice),
                       ResolvedOnDeviceModelTier(tier: .afm3CoreAdvanced, source: .inferred))
    }

    func test_resolver_eightGBDevice_isCore() {
        XCTAssertEqual(resolve(memory: eightGBDevice),
                       ResolvedOnDeviceModelTier(tier: .afm3Core, source: .inferred))
    }

    func test_resolver_memoryFloor_bothSides() {
        let floor = OnDeviceModelTierResolver.coreAdvancedMemoryFloorBytes
        XCTAssertEqual(resolve(memory: floor).tier, .afm3CoreAdvanced)
        XCTAssertEqual(resolve(memory: floor - 1).tier, .afm3Core)
    }

    /// The floor must separate the two classes as devices actually report
    /// them: an 8 GB phone reports under 8 GiB, a 12 GB phone under 12 GiB.
    func test_resolver_memoryFloor_sitsBetweenTheHardwareClasses() {
        let floor = OnDeviceModelTierResolver.coreAdvancedMemoryFloorBytes
        let gib: UInt64 = 1 << 30
        XCTAssertGreaterThan(floor, 8 * gib)
        XCTAssertLessThan(floor, 11 * gib)
    }

    func test_resolver_futureOS_stillUsesTheMemoryClass() {
        XCTAssertEqual(resolve(os: 28, memory: eightGBDevice).tier, .afm3Core)
        XCTAssertEqual(resolve(os: 28, memory: twelveGBDevice).tier, .afm3CoreAdvanced)
    }

    // MARK: Identifier suffixes

    func test_identifierSuffix_unknownKeepsTheBareIdentifier() {
        XCTAssertNil(OnDeviceModelTier.unknown.identifierSuffix)
    }

    func test_identifierSuffix_areDistinct() {
        let suffixes = OnDeviceModelTier.allCases.compactMap(\.identifierSuffix)
        XCTAssertEqual(Set(suffixes).count, OnDeviceModelTier.allCases.count - 1)
    }

    // MARK: Model identifiers (R3) — a wire format; pinned verbatim

    func test_modelIdentifier_onDevice_pinsAllFourStrings() {
        func id(_ tier: OnDeviceModelTier) -> String {
            ResolvedOnDeviceModelTier(tier: tier, source: .inferred).modelIdentifier(for: .z0Device)
        }
        XCTAssertEqual(id(.afm3CoreAdvanced), "apple.system.on-device.afm3-core-advanced")
        XCTAssertEqual(id(.afm3Core), "apple.system.on-device.afm3-core")
        XCTAssertEqual(id(.preAFM3), "apple.system.on-device.pre-afm3")
        XCTAssertEqual(id(.unknown), "apple.system.on-device")
    }

    func test_modelIdentifier_sourceDoesNotForkTheIdentifier() {
        let reported = ResolvedOnDeviceModelTier(tier: .afm3Core, source: .reported)
        let inferred = ResolvedOnDeviceModelTier(tier: .afm3Core, source: .inferred)
        XCTAssertEqual(reported.modelIdentifier(for: .z0Device), inferred.modelIdentifier(for: .z0Device))
    }

    func test_modelIdentifier_offDeviceZones_ignoreTheTier() {
        let tier = ResolvedOnDeviceModelTier(tier: .afm3CoreAdvanced, source: .inferred)
        XCTAssertEqual(tier.modelIdentifier(for: .z1AppleContent(reasoningLevel: .light)), "apple.pcc.light")
        XCTAssertEqual(tier.modelIdentifier(for: .z1AppleContentFree), "apple.cloud.content-free")
    }

    func test_modelIdentifier_onDevice_keepsTheHistoricalPrefix() {
        for tier in OnDeviceModelTier.allCases {
            let id = ResolvedOnDeviceModelTier(tier: tier, source: .inferred).modelIdentifier(for: .z0Device)
            XCTAssertTrue(id.hasPrefix("apple.system.on-device"), id)
        }
    }

    // MARK: Perf line (R4)

    func test_logFields_areEnumRawValuesOnly() {
        let fields = ResolvedOnDeviceModelTier(tier: .afm3CoreAdvanced, source: .inferred).logFields
        XCTAssertEqual(fields, "tier=afm3CoreAdvanced tier_source=inferred")
        XCTAssertEqual(ResolvedOnDeviceModelTier.unresolved.logFields, "tier=unknown tier_source=inferred")
    }

    // MARK: Cache

    func test_cache_startsUnresolved() {
        let cache = OnDeviceModelTierCache()
        XCTAssertFalse(cache.hasResolved)
        XCTAssertEqual(cache.current, .unresolved)
    }

    func test_cache_neverStoresUnknown() {
        let cache = OnDeviceModelTierCache()
        cache.store(.unresolved)
        XCTAssertFalse(cache.hasResolved)
    }

    func test_cache_storesAKnownTier_andInvalidateClearsIt() {
        let cache = OnDeviceModelTierCache()
        let known = ResolvedOnDeviceModelTier(tier: .afm3Core, source: .inferred)
        cache.store(known)
        XCTAssertTrue(cache.hasResolved)
        XCTAssertEqual(cache.current, known)

        cache.store(.unresolved)
        XCTAssertEqual(cache.current, known, "an unknown result must not overwrite a known tier")

        cache.invalidate()
        XCTAssertEqual(cache.current, .unresolved)
    }
}
