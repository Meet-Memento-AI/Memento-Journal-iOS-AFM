import XCTest
@testable import MeetMemento

final class AskPromptContractTests: XCTestCase {

    func test_ask4_versionAndHardBans() {
        let resolved = PromptRegistry.instructions(for: .ask)
        XCTAssertEqual(resolved.version, "ask@4")
        XCTAssertTrue(resolved.text.contains("Hard bans:"))
        XCTAssertTrue(resolved.text.contains("Never open a reply with \"You wrote\""))
        XCTAssertFalse(resolved.text.contains("(\"you wrote…\""))
        XCTAssertFalse(resolved.text.contains("three beats"))
    }

    func test_personalized_usesAsk4PlusP2() {
        let p = PromptPersonalization(
            firstName: "Ada",
            reflection: "I want to understand my stress",
            goals: ["Stress", "Clarity"],
            promptLens: "Lean toward stress patterns."
        )
        let resolved = PromptRegistry.instructions(for: .ask, personalization: p)
        XCTAssertEqual(resolved.version, "ask@4+p2")
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
        XCTAssertEqual(resolved.version, "ask@4+p2")
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
        XCTAssertEqual(resolved.version, "ask-degraded@4+p2")
        XCTAssertFalse(resolved.text.contains("my long reflection text"))
    }
}
