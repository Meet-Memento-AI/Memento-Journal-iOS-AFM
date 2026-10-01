import XCTest
@testable import withMemento

/// RT1 (MEM-333): cast gold turn-kind set vs `TurnClassifier`. Report-only —
/// does not assert the 90% / ±10pp retrieval gates.
final class TurnKindCastReportTests: XCTestCase {

    func test_castGoldFixture_hasAtLeast300Rows() throws {
        let file = try TurnKindGoldFixture.load()
        XCTAssertGreaterThanOrEqual(file.rowCount, 300)
        XCTAssertEqual(file.rows.count, file.rowCount)
    }

    func test_turnKindMismatch_scorerFiresOnMismatch() {
        let violations = ChatEvalScoring.turnKindMismatch(predicted: .followup, gold: .share)
        XCTAssertEqual(violations.map(\.code), ["route.turnKindMismatch"])
        XCTAssertTrue(violations[0].detail.contains("share"))
        XCTAssertTrue(violations[0].detail.contains("followup"))
        XCTAssertEqual(ChatEvalScoring.turnKindMismatch(predicted: .share, gold: .share), [])
    }

    /// Loads the stratified fixture, classifies each row, and prints metrics.
    /// Fails only if the fixture is missing or the scorer never fires across the set.
    func test_castGoldTurnKind_reportMetrics() throws {
        let file = try TurnKindGoldFixture.load()
        let metrics = TurnKindCastReport.metrics(rows: file.rows)

        var violationCount = 0
        for row in file.rows {
            violationCount += TurnKindCastReport.violations(for: row).count
        }
        XCTAssertEqual(violationCount, metrics.mismatchCount)
        XCTAssertGreaterThan(metrics.mismatchCount, 0, "fixture should include known classifier/gold disagreements")

        let report = TurnKindCastReport.renderMarkdown(metrics, fixture: file)
        print(report)
        print(String(format: "RT1_METRICS agreement=%.4f mismatchRate=%.4f goldFollowup=%.4f predFollowup=%.4f deltaPP=%+.2f",
                     metrics.agreementRate,
                     metrics.mismatchRate,
                     metrics.goldFollowupShare,
                     metrics.predictedFollowupShare,
                     metrics.followupShareDeltaPoints))

        // Report-only: record baseline, do not gate on plan thresholds yet.
        XCTAssertGreaterThan(metrics.rowCount, 0)
    }
}
