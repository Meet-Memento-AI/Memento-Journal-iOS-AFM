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
        XCTAssertEqual(resolved.version, "ask@3")
        XCTAssertFalse(resolved.text.contains("About this person"))
    }

    func test_personalizedPrompt_appendsSectionAndVersionSuffix() {
        let p = PromptPersonalization(
            firstName: "Sebastian",
            reflection: "I want to understand my stress patterns",
            goals: ["Self awareness", "Stress relief"]
        )
        let resolved = PromptRegistry.instructions(for: .ask, personalization: p)
        XCTAssertEqual(resolved.version, "ask@3+p")
        XCTAssertTrue(resolved.text.contains("About this person"))
        XCTAssertTrue(resolved.text.contains("Sebastian"))
        XCTAssertTrue(resolved.text.contains("I want to understand my stress patterns"))
        XCTAssertTrue(resolved.text.contains("Self awareness, Stress relief"))
        XCTAssertTrue(resolved.text.contains("never recite this back"))
    }

    func test_reflection_isTruncated() {
        let long = String(repeating: "a", count: 600)
        let p = PromptPersonalization(firstName: nil, reflection: long, goals: [])
        let resolved = PromptRegistry.instructions(for: .ask, personalization: p)
        XCTAssertFalse(resolved.text.contains(long))
        XCTAssertTrue(resolved.text.contains(String(repeating: "a", count: PromptRegistry.maxReflectionChars) + "…"))
    }

    func test_degradedVariant_skipsReflection_keepsGoals() {
        let p = PromptPersonalization(firstName: nil, reflection: "my long reflection text", goals: ["Honesty"])
        let resolved = PromptRegistry.instructions(for: .ask, degraded: true, personalization: p)
        XCTAssertEqual(resolved.version, "ask-degraded@3+p")
        XCTAssertFalse(resolved.text.contains("my long reflection text"))
        XCTAssertTrue(resolved.text.contains("Honesty"))
    }

    func test_summaryPrompt_ignoresPersonalization() {
        let p = PromptPersonalization(firstName: "Sam", reflection: nil, goals: ["Honesty"])
        let resolved = PromptRegistry.instructions(for: .summary, personalization: p)
        XCTAssertEqual(resolved.version, "summarize@1")
        XCTAssertFalse(resolved.text.contains("About this person"))
    }

    func test_fromLocalProfile_roundTrip() {
        UserDefaults.standard.set("  Sebastian ", forKey: "memento_first_name")
        LocalProfileStore.personalizationText = "understand myself better"
        LocalProfileStore.selectedGoals = ["Self awareness"]

        let p = PromptPersonalization.fromLocalProfile()
        XCTAssertEqual(p.firstName, "Sebastian")
        XCTAssertEqual(p.reflection, "understand myself better")
        XCTAssertEqual(p.goals, ["Self awareness"])
        XCTAssertFalse(p.isEmpty)
    }

    func test_fromLocalProfile_emptyWhenNothingStored() {
        UserDefaults.standard.removeObject(forKey: "memento_first_name")
        LocalProfileStore.clearAll()
        XCTAssertTrue(PromptPersonalization.fromLocalProfile().isEmpty)
    }
}
