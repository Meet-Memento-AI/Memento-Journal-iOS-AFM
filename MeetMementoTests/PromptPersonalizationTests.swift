import XCTest
@testable import MeetMemento

final class PromptPersonalizationTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "memento_first_name")
        LocalProfileStore.clearAll()
        super.tearDown()
    }

    func test_emptyPersonalization_keepsBasePromptAndVersion() {
        let resolved = PromptRegistry.instructions(for: .ask, personalization: .none)
        XCTAssertEqual(resolved.version, "ask@8")
        // Assert on the section HEADER, not the bare phrase. ask@4 added
        // `Never recite … the "About this person" section` to the Hard bans, so
        // the base prompt legitimately contains that phrase and the old
        // `contains("About this person")` assertion has been failing on main
        // ever since. What this test actually means is "no personalization
        // section was appended", and only the header proves that.
        XCTAssertFalse(resolved.text.contains("About this person (quiet background"))
    }

    func test_personalizedPrompt_appendsSectionAndVersionSuffix() {
        let p = PromptPersonalization(
            firstName: "Sebastian",
            reflection: "I want to understand my stress patterns",
            goals: ["Awareness", "Stress"],
            promptLens: "Lean toward noticing stress patterns without prescribing fixes."
        )
        let resolved = PromptRegistry.instructions(for: .ask, personalization: p)
        XCTAssertEqual(resolved.version, "ask@8+p2")
        XCTAssertTrue(resolved.text.contains("About this person"))
        XCTAssertTrue(resolved.text.contains("Sebastian"))
        // Themes/lens present → raw reflection is not quoted (anti-loop).
        XCTAssertFalse(resolved.text.contains("I want to understand my stress patterns"))
        XCTAssertTrue(resolved.text.contains("Awareness, Stress"))
        XCTAssertTrue(resolved.text.contains("Personalization lens:"))
        XCTAssertTrue(resolved.text.contains("never recite this back"))
    }

    func test_reflection_isTruncated() {
        let long = String(repeating: "a", count: 600)
        let p = PromptPersonalization(firstName: nil, reflection: long, goals: [], promptLens: nil)
        let resolved = PromptRegistry.instructions(for: .ask, personalization: p)
        XCTAssertFalse(resolved.text.contains(long))
        XCTAssertTrue(resolved.text.contains(String(repeating: "a", count: PromptRegistry.maxReflectionChars) + "…"))
    }

    func test_degradedVariant_skipsReflection_keepsGoals() {
        let p = PromptPersonalization(
            firstName: nil,
            reflection: "my long reflection text",
            goals: ["Honesty"],
            promptLens: nil
        )
        let resolved = PromptRegistry.instructions(for: .ask, degraded: true, personalization: p)
        XCTAssertEqual(resolved.version, "ask-degraded@8+p2")
        XCTAssertFalse(resolved.text.contains("my long reflection text"))
        XCTAssertTrue(resolved.text.contains("Honesty"))
    }

    func test_summaryPrompt_ignoresPersonalization() {
        let p = PromptPersonalization(firstName: "Sam", reflection: nil, goals: ["Honesty"], promptLens: nil)
        let resolved = PromptRegistry.instructions(for: .summary, personalization: p)
        XCTAssertEqual(resolved.version, "summarize@1")
        XCTAssertFalse(resolved.text.contains("About this person"))
    }

    func test_profileEstimatePrompt_isBundled() {
        let resolved = PromptRegistry.instructions(for: .profileEstimate)
        XCTAssertEqual(resolved.version, "profile-estimate@1")
        XCTAssertTrue(resolved.text.contains("closed catalog") || resolved.text.contains("theme ids"))
    }

    func test_fromLocalProfile_roundTrip() {
        UserDefaults.standard.set("  Sebastian ", forKey: "memento_first_name")
        LocalProfileStore.experienceProfile = ExperienceProfile(
            reflection: "understand myself better",
            confirmedThemeIds: ["awareness"],
            suggestedThemeIds: ["awareness", "stress"],
            promptLens: "Lean toward self-awareness questions.",
            catalogVersion: ThemeCatalog.catalogVersion,
            builtAt: Date(),
            modelIdentifier: nil
        )

        let p = PromptPersonalization.fromLocalProfile()
        XCTAssertEqual(p.firstName, "Sebastian")
        XCTAssertEqual(p.reflection, "understand myself better")
        XCTAssertEqual(p.goals, ["Awareness"])
        XCTAssertEqual(p.promptLens, "Lean toward self-awareness questions.")
        XCTAssertFalse(p.isEmpty)
    }

    func test_fromLocalProfile_emptyWhenNothingStored() {
        UserDefaults.standard.removeObject(forKey: "memento_first_name")
        LocalProfileStore.clearAll()
        XCTAssertTrue(PromptPersonalization.fromLocalProfile().isEmpty)
    }
}
