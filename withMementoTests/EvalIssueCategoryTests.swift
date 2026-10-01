import XCTest

final class EvalIssueCategoryTests: XCTestCase {
    func test_categoriesHaveStableRawValues() {
        XCTAssertEqual(EvalIssueCategory.deviceGate.rawValue, "device_gate")
        XCTAssertFalse(EvalIssueCategory.allCases.isEmpty)
    }
}
