//
//  PlaceNameFormatterTests.swift
//  withMementoTests
//

import XCTest
@testable import withMemento

final class PlaceNameFormatterTests: XCTestCase {
    func test_format_localityAndAdministrativeArea() {
        XCTAssertEqual(
            PlaceNameFormatter.format(locality: "Dallas", administrativeArea: "TX"),
            "Dallas, TX"
        )
    }

    func test_format_fallsBackToLocalityThenName() {
        XCTAssertEqual(
            PlaceNameFormatter.format(locality: "Dallas", administrativeArea: nil),
            "Dallas"
        )
        XCTAssertEqual(
            PlaceNameFormatter.format(locality: nil, administrativeArea: nil, name: "Home"),
            "Home"
        )
        XCTAssertNil(PlaceNameFormatter.format(locality: "  ", administrativeArea: nil, name: " "))
    }

    func test_storedEntry_andEnvelope_haveNoCoordinateFields() throws {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let schema = try String(
            contentsOf: repo.appendingPathComponent("withMemento/Models/JournalSchema.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(schema.contains("placeName"))
        XCTAssertFalse(schema.contains("latitude"))
        XCTAssertFalse(schema.contains("longitude"))
        XCTAssertFalse(schema.contains("CLLocation"))

        let envelope = try String(
            contentsOf: repo.appendingPathComponent("withMemento/Services/JournalService.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(envelope.contains("placeName"))
        XCTAssertFalse(envelope.contains("latitude"))
        XCTAssertFalse(envelope.contains("longitude"))
    }
}
