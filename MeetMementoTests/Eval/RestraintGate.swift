import XCTest
@testable import MeetMemento

/// Spec 022 / 045 R6 — observation suppression on ordinary fixtures.
/// Report-only until Session 8/9 produce two warehoused runs.
final class RestraintGate: XCTestCase {
    func test_restraintGate_reportOnly() throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(
            env["TEST_RUNNER_RESTRAINT_GATE"] == "1" || env["RESTRAINT_GATE"] == "1",
            "set TEST_RUNNER_RESTRAINT_GATE=1"
        )

        let fixtures: [(salience: Double, expectObservation: Bool)] = [
            (0.1, false),
            (0.2, false),
            (0.39, false),
            (0.4, true),
            (0.8, true),
            (1.0, true)
        ]
        let suppressed = fixtures.filter { !EntryReflectionPolicy.shouldWriteObservation(salience: $0.salience) }
        let rate = Double(suppressed.count) / Double(fixtures.count)
        print("RestraintGate observation-suppressed rate: \(rate) (\(suppressed.count)/\(fixtures.count))")
        XCTAssertGreaterThan(rate, 0)
    }
}
