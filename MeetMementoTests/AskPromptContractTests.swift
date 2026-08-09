import XCTest
@testable import MeetMemento

final class AskPromptContractTests: XCTestCase {

    func test_ask5_versionAndHardBans() {
        let resolved = PromptRegistry.instructions(for: .ask)
        XCTAssertEqual(resolved.version, "ask@5")
        XCTAssertTrue(resolved.text.contains("Hard bans:"))
        XCTAssertTrue(resolved.text.contains("Never open a reply with \"You wrote\""))
        XCTAssertFalse(resolved.text.contains("(\"you wrote…\""))
        XCTAssertFalse(resolved.text.contains("three beats"))
    }

    /// ask@5: ref numbers are internal to `citedRefs`. The model must be told,
    /// in both the full and degraded prompts, never to write them into the
    /// reply — the labels sit in its context as the naming convention for
    /// entries, so without an explicit ban it reproduces them in prose.
    func test_ask5_bansReferenceMarkersInTheReply() {
        for degraded in [false, true] {
            let text = PromptRegistry.instructions(for: .ask, degraded: degraded).text
            XCTAssertTrue(
                text.contains("Never write a reference marker in the reply"),
                "degraded=\(degraded): the marker ban must be explicit"
            )
            XCTAssertTrue(text.contains("[ref 2]"), "degraded=\(degraded): ban should show the form")
        }
    }

    /// The context block still labels entries `[ref N | date]` — that is the
    /// addressing scheme `citedRefs` depends on, and removing it would break
    /// citations entirely. The prompt must keep asking for those numbers in the
    /// field even while banning them from the body.
    func test_ask5_stillCollectsCitedRefs() {
        let text = PromptRegistry.instructions(for: .ask).text
        XCTAssertTrue(text.contains("citedRefs"), "citedRefs must still be requested")
    }

    func test_personalized_usesAsk5PlusP2() {
        let p = PromptPersonalization(
            firstName: "Ada",
            reflection: "I want to understand my stress",
            goals: ["Stress", "Clarity"],
            promptLens: "Lean toward stress patterns."
        )
        let resolved = PromptRegistry.instructions(for: .ask, personalization: p)
        XCTAssertEqual(resolved.version, "ask@5+p2")
        XCTAssertTrue(resolved.text.contains("Themes they chose: Stress, Clarity"))
        XCTAssertTrue(resolved.text.contains("Personalization lens:"))
        // With themes/lens present, raw reflection must not be quoted into L1.
        XCTAssertFalse(resolved.text.contains("I want to understand my stress"))
    }

    func test_personalized_quotesReflectionOnlyWhenNoThemesOrLens() {
        let p = PromptPersonalization(
            firstName: nil,
            reflection: "I want to understand my stress patterns more deeply",
            goals: [],
            promptLens: nil
        )
        let resolved = PromptRegistry.instructions(for: .ask, personalization: p)
        XCTAssertEqual(resolved.version, "ask@5+p2")
        XCTAssertTrue(resolved.text.contains("I want to understand my stress patterns more deeply"))
    }

    func test_degraded_skipsReflectionEvenWithoutThemes() {
        let p = PromptPersonalization(
            firstName: nil,
            reflection: "my long reflection text",
            goals: [],
            promptLens: nil
        )
        let resolved = PromptRegistry.instructions(for: .ask, degraded: true, personalization: p)
        XCTAssertEqual(resolved.version, "ask-degraded@5+p2")
        XCTAssertFalse(resolved.text.contains("my long reflection text"))
    }
}
