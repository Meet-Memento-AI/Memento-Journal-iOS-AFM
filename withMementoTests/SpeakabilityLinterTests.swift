import XCTest
@testable import MeetMemento

/// Per-pattern fixture suite mirroring `scripts/ci/speakability_lint.py`'s
/// selftest (spec 018 R9 exit criteria: one fixture per pattern, and a
/// failure names REQ-VOX-006). Fixtures are copied verbatim from the Python
/// VIOLATING/CLEAN dicts — keep the two in sync.
final class SpeakabilityLinterTests: XCTestCase {

    private func assertViolation(
        _ text: String, pattern expected: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        do {
            try SpeakabilityLinter.validate(text)
            XCTFail("expected \(expected) violation, none thrown", file: file, line: line)
        } catch let violation as SpeakabilityViolation {
            XCTAssertEqual(violation.patternName, expected, file: file, line: line)
            XCTAssertTrue(violation.description.contains("REQ-VOX-006"),
                          "violation must name REQ-VOX-006", file: file, line: line)
        } catch {
            XCTFail("unexpected error type: \(error)", file: file, line: line)
        }
    }

    // MARK: - Violating fixtures (one per pattern)

    func test_detectsMarkdownHeading() {
        assertViolation("# Your week\nYou wrote often.", pattern: "markdown-heading")
    }

    func test_detectsEmphasisOrCode() {
        assertViolation("You felt *calmer* this week.", pattern: "markdown-emphasis-or-code")
    }

    func test_detectsListMarker() {
        assertViolation("This week:\n- you ran twice\n- you slept well", pattern: "list-marker")
    }

    func test_detectsURL() {
        assertViolation("See https://example.com for more.", pattern: "url")
    }

    func test_detectsBlankLineRun() {
        assertViolation("You wrote on Monday.\n\n\nThen again on Friday.", pattern: "blank-line-run")
    }

    func test_detectsEmoji() {
        assertViolation("You seemed happy this week \u{1F600}", pattern: "emoji")
    }

    // MARK: - Clean fixtures (allowlist: years, clock times, ordinary prose)

    func test_cleanProsePasses() {
        let clean = [
            "You wrote three entries this week, mostly in the evening.",
            "In 2026 you started journaling at 9:30 in the morning, and it stuck.",
            "You mentioned your sister twice, both times with warmth.",
            "There was a quieter stretch mid-week, then you picked it back up.",
        ]
        for text in clean {
            XCTAssertNoThrow(try SpeakabilityLinter.validate(text), "flagged clean: \(text)")
        }
    }

    // MARK: - Violation surface

    func test_violationCarriesRangeAndSnippet() {
        do {
            try SpeakabilityLinter.validate("See https://example.com for more.")
            XCTFail("expected a violation")
        } catch let violation as SpeakabilityViolation {
            XCTAssertEqual(violation.snippet, "https://")
            XCTAssertFalse(violation.range.isEmpty)
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }
}
