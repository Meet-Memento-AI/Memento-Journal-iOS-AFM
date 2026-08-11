//
//  TrustZoneTests.swift
//  MeetMementoTests
//
//  Spec 014 R1 acceptance: the TrustZone contract compiles with its cases,
//  round-trips through Codable per case (spec 015 persistence depends on it),
//  and there is no way to represent Z2.
//

import XCTest
@testable import MeetMemento

final class TrustZoneTests: XCTestCase {

    private let allZones: [TrustZone] = [
        .z0Device,
        .z1AppleContent(reasoningLevel: .light),
        .z1AppleContent(reasoningLevel: .moderate),
        .z1AppleContent(reasoningLevel: .deep),
        .z1AppleContentFree
    ]

    func test_codableRoundTrip_everyCase() throws {
        for zone in allZones {
            let data = try JSONEncoder().encode(zone)
            let decoded = try JSONDecoder().decode(TrustZone.self, from: data)
            XCTAssertEqual(decoded, zone, "TrustZone must round-trip losslessly: \(zone)")
        }
    }

    func test_reasoningLevel_codableRoundTrip() throws {
        for level in PCCReasoningLevel.allCases {
            let data = try JSONEncoder().encode(level)
            let decoded = try JSONDecoder().decode(PCCReasoningLevel.self, from: data)
            XCTAssertEqual(decoded, level)
        }
    }

    func test_contentOffDevice_onlyForZ1Content() {
        XCTAssertFalse(TrustZone.z0Device.carriesContentOffDevice)
        XCTAssertFalse(TrustZone.z1AppleContentFree.carriesContentOffDevice)
        for level in PCCReasoningLevel.allCases {
            XCTAssertTrue(TrustZone.z1AppleContent(reasoningLevel: level).carriesContentOffDevice)
        }
    }

    func test_identifiers_areUniqueAndContentFree() {
        let ids = allZones.map(\.identifier)
        XCTAssertEqual(Set(ids).count, ids.count, "zone identifiers must be unique")
        for id in ids {
            XCTAssertFalse(id.isEmpty)
        }
    }
}
