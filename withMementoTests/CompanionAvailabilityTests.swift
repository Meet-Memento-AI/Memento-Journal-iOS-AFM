import XCTest
@testable import withMemento

@MainActor
final class CompanionAvailabilityTests: XCTestCase {
    func test_CompanionAvailability_surfacesReasonBeforeAnySend() async {
        let availability = CompanionAvailability { .unavailable(.deviceNotEligible) }
        XCTAssertNil(availability.unavailableReason)

        await availability.refresh()

        XCTAssertEqual(availability.unavailableReason, .deviceNotEligible)
    }

    func test_CompanionAvailability_clearsOnceTheModelIsReady() async {
        var current: IntelligenceAvailability = .unavailable(.modelNotReady)
        let availability = CompanionAvailability { current }

        await availability.refresh()
        XCTAssertEqual(availability.unavailableReason, .modelNotReady)

        current = .available(.z0Device)
        await availability.refresh()
        XCTAssertNil(availability.unavailableReason)
    }
}
